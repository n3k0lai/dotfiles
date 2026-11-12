# Grok Bot desktop (proprietary Electron app).
# Release feed: https://api2.cursor.sh/updates/api/download/stable/linux-x64/sand
# Pin version + commitSha together. The deb URL includes the commit.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libGL,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libsecret,
  libuuid,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  libxcb,
  libxkbfile,
  libxshmfence,
}:

stdenv.mkDerivation rec {
  pname = "grok-bot";
  version = "1.0.1";

  src = fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/7eb488cd12ea2e65065a6b227f3ab49160b618bd/linux/x64/grok-bot_${version}_amd64.deb";
    hash = "sha256-hghqhKmVg2uMvwncqzOr4LD954LNn6W5ikJ+3nEcwzc=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libGL
    libdrm
    libgbm
    libglvnd
    libnotify
    libsecret
    libuuid
    libxkbcommon
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc
    systemd
    wayland
    libx11
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
    libxcb
    libxkbfile
    libxshmfence
  ];

  # The deb's /opt path contains a space, which breaks Electron's sandbox
  # fallback. Install under lib/grok-bot instead.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/share"
    cp -a "opt/Grok Bot" "$out/lib/grok-bot"
    chmod 0755 "$out/lib/grok-bot/chrome-sandbox" || true

    cp -a usr/share/applications "$out/share/"
    cp -a usr/share/icons "$out/share/"

    runHook postInstall
  '';

  dontWrapGApps = true;

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd libGL ]}:/run/opengl-driver/lib"
      --set __EGL_VENDOR_LIBRARY_DIRS /run/opengl-driver/share/glvnd/egl_vendor.d
      --add-flags "--ozone-platform=wayland --enable-features=WaylandLinuxDrmSyncobj"
    )
  '';

  postFixup = ''
    makeWrapper "$out/lib/grok-bot/grok-bot" "$out/bin/grok-bot" "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "Grok Bot desktop agent";
    homepage = "https://cursor.com/download/bot";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "grok-bot";
  };
}
