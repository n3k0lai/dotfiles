{
  description = "NixOS configurations for kiss, blade, ene, rook, pati0 (patio Pi), droid, and waves";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Waves and droid stay on 25.05. nix-darwin is glitchy until Omarchy
    # runs on M4. nix-on-droid is still release-24.05 and must not ride
    # the fleet pin.
    nixpkgs-25_05.url = "github:NixOS/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-25_05 = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs-25_05";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      # Upstream versioned release. PRs still go back to NousResearch/hermes-agent.
      # n3k0lai/hermes has no release tags (main last moved 2026-08-29).
      url = "github:NousResearch/hermes-agent/v2026.9.24";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs-25_05";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };

    # Core Linux video editor (our fork). flake = false: raw source for rustPlatform.
    opencut-src = {
      url = "github:n3k0lai/OpenCut";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-25_05, home-manager, home-manager-25_05, agenix, emacs-overlay, hermes-agent, nix-on-droid, nix-darwin, nix-homebrew, opencut-src, ... }:
  let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };
  in {
    packages.x86_64-linux.opencut = pkgs-unstable.callPackage ./modules/editors/opencut/package.nix {
      src = opencut-src;
    };

    nixosConfigurations = {
      # Desktop workstation
      kiss = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit pkgs-unstable opencut-src hermes-agent; };
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
          ./hosts/kiss.nix
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
          {
            nixpkgs.overlays = [
              agenix.overlays.default
              emacs-overlay.overlays.default
            ];
          }
        ];
      };

      # DigitalOcean server
      ene = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit hermes-agent; };
        modules = [
          ./hosts/ene-hardware.nix
          ./configuration-server.nix
          ./hosts/ene.nix
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
          hermes-agent.nixosModules.default
          {
            nixpkgs.overlays = [ agenix.overlays.default ];
          }
        ];
      };

      # Artemis telemetry server
      artemis = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/artemis-hardware.nix
          ./configuration-server.nix
          ./hosts/artemis.nix
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
          {
            nixpkgs.overlays = [ agenix.overlays.default ];
          }
        ];
      };

      # Razer Blade portable workstation + Forscan VM host
      # Uses unstable nixpkgs: nixos-25.05 lacks modules.builtin.modinfo fix for
      # linux 6.12 initrd (modules-shrunk build fails). See nixpkgs#484105.
      blade = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          ./hosts/blade-hardware.nix
          ./hosts/blade.nix
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
          { nixpkgs.overlays = [ agenix.overlays.default ]; }
        ];
      };

      # Work agent server (formerly Chat)
      rook = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit hermes-agent; };
        modules = [
          ./hosts/rook-hardware.nix
          ./configuration-server.nix
          ./hosts/rook.nix
          # bin/default.nix (fish functions) comes via configuration-server.nix
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
          hermes-agent.nixosModules.default
          {
            nixpkgs.overlays = [ agenix.overlays.default ];
          }
        ];
      };

      # Patio edge Pi (aarch64) — camera + BT fans; NOT a second HA
      # Switch on-device: nixos-rebuild switch --flake .#pati0
      pati0 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./hosts/pati0-hardware.nix
          ./hosts/pati0.nix
        ];
      };
    };

    # M4 MacBook Air (nix-darwin)
    darwinConfigurations.waves = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit self agenix;
        hostname = "waves";
        username = "nicho";
        inputs = { nixpkgs = nixpkgs-25_05; inherit agenix; };
      };
      modules = [
        ./hosts/waves.nix
        home-manager-25_05.darwinModules.home-manager
        {
          nixpkgs.overlays = [ agenix.overlays.default ];
        }
      ];
    };

    # Android phone (nix-on-droid)
    nixOnDroidConfigurations.droid = nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import nixpkgs-25_05 { system = "aarch64-linux"; config.allowUnfree = true; };
      modules = [ ./hosts/droid.nix ];
      # nix-on-droid 24.05 otherwise uses its own 2024 home-manager input.
      # Keep the 25.05 pin. The fleet home-manager is 26.05.
      home-manager-path = home-manager-25_05.outPath;
      extraSpecialArgs = {
        pkgs-unstable = import nixpkgs-unstable {
          system = "aarch64-linux";
          config.allowUnfree = true;
        };
      };
    };
  };
}
