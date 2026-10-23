{ lib, stdenv, fetchFromGitHub, pkg-config, libusb1 }:

stdenv.mkDerivation {
  pname = "ems-flasher";
  version = "unstable-2017-12-13";

  src = fetchFromGitHub {
    owner = "mikeryan";
    repo = "ems-flasher";
    rev = "b88640a6aa2644e3aae7b63970d683b71f286e41";
    hash = "sha256-kw144i7maifm4qbvYgZBethAg6MYGskoZ+DVAdlm40Q=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libusb1 ];

  # The upstream install step reloads udev; NixOS handles that itself.
  postPatch = ''
    substituteInPlace Makefile.tmpl --replace-fail "udevadm control --reload-rules" "true"
  '';

  configurePhase = ''
    runHook preConfigure
    mkdir -p $out/lib/udev/rules.d
    CFLAGS="-O2 -Wall -std=c99 -fcommon" ./config.sh --prefix $out --udevrulesdir $out/lib/udev/rules.d
    runHook postConfigure
  '';

  preInstall = ''
    mkdir -p $out/bin $out/share/ems-flasher $out/share/man/man1 $out/lib/udev/rules.d
  '';

  meta = {
    description = "Linux flasher for the EMS 64M USB Game Boy flash cart";
    homepage = "https://github.com/mikeryan/ems-flasher";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "ems-flasher";
  };
}
