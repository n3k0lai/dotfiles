{ pkgs, ... }:

let
  fortune-zh = pkgs.stdenv.mkDerivation {
    name = "fortune-zh";
    src = pkgs.fetchFromGitHub {
      owner = "ruanyf";
      repo = "fortunes";
      rev = "master";
      sha256 = "sha256-O258vnAHQ3RrJnMPmVntmkj+RSfpHsf/YKJcLZd0owc=";
    };
    
    buildInputs = [ pkgs.fortune ];
    
    installPhase = ''
      mkdir -p $out/share/games/fortunes
      cp data/chinese $out/share/games/fortunes/
      
      # Generate index file
      ${pkgs.fortune}/bin/strfile data/chinese $out/share/games/fortunes/chinese.dat
    '';
  };
in
{
  fortune-with-zh = pkgs.symlinkJoin {
    name = "fortune-with-zh";
    paths = [ pkgs.fortune fortune-zh ];
  };
}
