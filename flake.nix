{
  description = "NixOS configurations for kiss (desktop), ene (server), rook (work agent server), droid (Android), and waves (macOS)";

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
      url = "github:NousResearch/hermes-agent";
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
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, agenix, emacs-overlay, hermes-agent, nix-on-droid, nix-darwin, nix-homebrew, ... }:
  let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };
  in {
    nixosConfigurations = {
      # Desktop workstation
      kiss = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit pkgs-unstable; };
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
        modules = [
          ./hosts/ene-hardware.nix
          ./configuration-server.nix
          ./hosts/ene.nix
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
          agenix.nixosModules.default
          {
            nixpkgs.overlays = [ agenix.overlays.default ];
          }
        ];
      };

      # Work agent server (formerly Chat)
      rook = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/rook-hardware.nix
          ./configuration-server.nix
          ./hosts/rook.nix
          ./bin/default.nix
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
          hermes-agent.nixosModules.default
          {
            nixpkgs.overlays = [ agenix.overlays.default ];
          }
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
