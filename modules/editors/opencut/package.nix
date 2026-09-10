# n3k0lai/OpenCut desktop app (GPUI). Built from the flake `opencut-src` input.
{
  lib,
  rustPlatform,
  pkg-config,
  cmake,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  fontconfig,
  freetype,
  openssl,
  vulkan-loader,
  wayland,
  libxkbcommon,
  libx11,
  libxcb,
  libGL,
  zlib,
  alsa-lib,
  stdenv,
  src,
}:

rustPlatform.buildRustPackage rec {
  pname = "opencut";
  version = "0.1.0";

  inherit src;

  cargoLock.lockFile = src + "/Cargo.lock";

  cargoBuildFlags = [ "--package=opencut-desktop" ];

  doCheck = false;
  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    pkg-config
    cmake
    makeWrapper
    copyDesktopItems
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    fontconfig
    freetype
    openssl
    zlib
    alsa-lib
    libxkbcommon
    wayland
    libx11
    libxcb
    libGL
  ];

  env.OPENSSL_NO_VENDOR = true;

  desktopItems = [
    (makeDesktopItem {
      name = "opencut";
      desktopName = "OpenCut";
      genericName = "Video Editor";
      comment = "Open-source video editor";
      exec = "opencut %F";
      icon = "opencut";
      terminal = false;
      categories = [
        "AudioVideo"
        "AudioVideoEditing"
        "Video"
      ];
    })
  ];

  postInstall = ''
    install -Dm644 ${src}/brand/marks/icon.svg \
      $out/share/icons/hicolor/scalable/apps/opencut.svg
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram $out/bin/opencut-desktop \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libGL
          vulkan-loader
          wayland
          libxkbcommon
        ]
      }
  '';

  meta = {
    description = "OpenCut desktop video editor (n3k0lai fork)";
    homepage = "https://github.com/n3k0lai/OpenCut";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "opencut";
  };
}
