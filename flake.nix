{
  description = "NixOS configurations for kiss (desktop), ene (server), chat (home server), and droid (Android)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
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

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, agenix, emacs-overlay, nix-on-droid, ... }:
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
          {
            nixpkgs.overlays = [ agenix.overlays.default ];
          }
        ];
      };

      # Home server
      chat = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/chat-hardware.nix
          ./configuration-server.nix
          ./hosts/chat.nix
          agenix.nixosModules.default
          {
            nixpkgs.overlays = [ agenix.overlays.default ];
          }
        ];
      };
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
