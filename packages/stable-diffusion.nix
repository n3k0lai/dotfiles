# https://github.com/virchau13/automatic1111-webui-nix/

{ lib, stdenv, fetchFromGitHub, my, ... }:

stdenv.mkDerivation {
  name = "adl";

  src = fetchFromGitHub {
    owner = "AUTOMATIC1111";
    repo = "stable-diffusion-webui";
    rev = "4ae1883e376b71033c6ecc6874421bac4b86d59d";
    sha256 = "4ae1883e376b71033c6ecc6874421bac4b86d59d";
  };
  src = fetchFromGitHub {
    owner = "AUTOMATIC1111";
    repo = "stable-diffusion-webui";
    rev = "4ae1883e376b71033c6ecc6874421bac4b86d59d";
    sha256 = "4ae1883e376b71033c6ecc6874421bac4b86d59d";
  };

  phases = "installPhase";
  installPhase = ''
    cp automatic1111-webui-nix/*.nix stable-diffusion-webui/
    cd stable-diffusion-webui
    git add *.nix
    nix develop
  '';

  meta = {
    homepage = "https://github.com/virchau13/automatic1111-webui-nix";
    description = "stable-diffusion-webui for CUDA and ROCm on NixOS";
    license = lib.licenses.MIT;
    platforms = [ "x86_64-linux" ];
    maintainers = [];
  };
}