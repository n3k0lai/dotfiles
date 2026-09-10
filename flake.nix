{
  description = "NixOS configurations for kiss, blade, ene, rook, pati0 (patio Pi), droid, and waves";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
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
      # Version we manage. PRs go back to NousResearch/hermes-agent.
      url = "github:n3k0lai/hermes";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
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

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, agenix, emacs-overlay, hermes-agent, nix-on-droid, nix-darwin, nix-homebrew, opencut-src, ... }:
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
        specialArgs = { inherit pkgs-unstable opencut-src; };
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
        inputs = { inherit nixpkgs agenix; };
      };
      modules = [
        ./hosts/waves.nix
        home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = [ agenix.overlays.default ];
        }
      ];
    };

    # Android phone (nix-on-droid)
    nixOnDroidConfigurations.droid = nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import nixpkgs { system = "aarch64-linux"; config.allowUnfree = true; };
      modules = [ ./hosts/droid.nix ];
      extraSpecialArgs = {
        pkgs-unstable = import nixpkgs-unstable {
          system = "aarch64-linux";
          config.allowUnfree = true;
        };
      };
    };
  };
}
