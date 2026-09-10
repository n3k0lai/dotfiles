# OpenCut — core Linux video editor (fork: github.com/n3k0lai/OpenCut)
#
# Packaged GPUI binary is `opencut-desktop`. `opencut` is a launcher that
# logs to ~/.local/state/opencut/opencut.log (and the terminal, if any).
# `dev.enable` runs `cargo run` from a local checkout instead.
#
#   opencut              launch (dev or packaged)
#   opencut --packaged   force the Nix binary
#   opencut logs         tail the log
#
# Bump the packaged src with: nix flake update opencut-src
{
  config,
  lib,
  pkgs,
  pkgs-unstable ? pkgs,
  opencut-src ? null,
  ...
}:

let
  cfg = config.modules.editors.opencut;
  rust = pkgs-unstable;

  opencutPkg = rust.callPackage ./opencut/package.nix {
    src = opencut-src;
  };

  packagedBin = "${opencutPkg}/bin/opencut-desktop";

  nativeLibs = with rust; [
    openssl
    fontconfig
    freetype
    wayland
    libxkbcommon
    libx11
    libxcb
    libGL
    vulkan-loader
    alsa-lib
    zlib
  ];

  pkgConfigPath = lib.makeSearchPath "lib/pkgconfig" (
    with rust;
    [
      openssl.dev
      fontconfig.dev
      freetype.dev
      wayland.dev
      libxkbcommon
      libx11.dev
      libxcb
      libGL.dev
      alsa-lib.dev
      zlib.dev
    ]
  );

  opencut = rust.writeShellScriptBin "opencut" ''
    set -euo pipefail

    logdir="''${XDG_STATE_HOME:-$HOME/.local/state}/opencut"
    mkdir -p "$logdir"
    log="$logdir/opencut.log"

    stamp() {
      printf '%s\n' "[$(${rust.coreutils}/bin/date -Iseconds)] $*" >>"$log"
    }

    run() {
      local cmd="$1"
      shift
      stamp "start cmd=$cmd rust_log=''${RUST_LOG:-} packaged=${packagedBin}"
      if [ -t 2 ]; then
        "$cmd" "$@" 2> >(${rust.coreutils}/bin/tee -a "$log" >&2)
      else
        "$cmd" "$@" >>"$log" 2>&1
      fi
      local st=$?
      stamp "exit $st"
      return $st
    }

    case "''${1:-}" in
      logs|--logs|-l)
        exec ${rust.coreutils}/bin/tail -F "$log"
        ;;
      --packaged)
        shift
        export RUST_LOG="''${RUST_LOG:-info}"
        export RUST_BACKTRACE="''${RUST_BACKTRACE:-1}"
        run ${packagedBin} "$@"
        ;;
      --help|-h)
        echo "opencut — OpenCut launcher"
        echo "  opencut              launch"
        echo "  opencut --packaged   Nix-built binary (skip cargo)"
        echo "  opencut logs         tail ~/.local/state/opencut/opencut.log"
        echo "  log file: $log"
        echo "  mode: ${if cfg.dev.enable then "dev (cargo @ ${cfg.dev.repoPath})" else "packaged"}"
        ;;
      *)
        export RUST_BACKTRACE="''${RUST_BACKTRACE:-1}"
        ${lib.optionalString cfg.dev.enable ''
          repo="${cfg.dev.repoPath}"
          force_packaged="''${OPENCUT_PACKAGED:-0}"
          if [ "$force_packaged" != 1 ] && [ -f "$repo/apps/desktop/Cargo.toml" ]; then
            export RUST_LOG="''${RUST_LOG:-debug}"
            export CARGO_HOME="''${CARGO_HOME:-$HOME/.cache/opencut/cargo}"
            export OPENSSL_NO_VENDOR=1
            export LIBCLANG_PATH="${rust.libclang.lib}/lib"
            export PKG_CONFIG_PATH="${pkgConfigPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
            export LD_LIBRARY_PATH="${lib.makeLibraryPath nativeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export PATH="${lib.makeBinPath (with rust; [ rustc cargo pkg-config cmake clang stdenv.cc ])}:$PATH"
            mkdir -p "$CARGO_HOME"
            stamp "dev cargo run -p opencut-desktop ($repo)"
            if [ ! -t 2 ] && command -v notify-send >/dev/null; then
              notify-send -a opencut "OpenCut" "dev build — logs: $log" || true
            fi
            cd "$repo"
            run cargo run --package opencut-desktop -- "$@"
            exit $?
          fi
          if [ "$force_packaged" != 1 ]; then
            stamp "dev enabled but $repo missing — packaged fallback"
          fi
        ''}
        export RUST_LOG="''${RUST_LOG:-info}"
        run ${packagedBin} "$@"
        ;;
    esac
  '';
in
{
  options.modules.editors.opencut = {
    enable = lib.mkEnableOption "OpenCut video editor (n3k0lai fork)";

    dev = {
      enable = lib.mkEnableOption ''
        Run from a local checkout with cargo instead of the Nix binary.
        Falls back to packaged if the checkout is missing.
      '';

      repoPath = lib.mkOption {
        type = lib.types.str;
        default = "/home/nicho/Code/OpenCut";
        description = "Local n3k0lai/OpenCut checkout used when dev.enable is true";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = opencut-src != null;
        message = "modules.editors.opencut needs flake input opencut-src in specialArgs";
      }
    ];

    environment.systemPackages = [
      opencutPkg
      opencut
    ] ++ lib.optionals cfg.dev.enable (
      with rust;
      [
        rustc
        cargo
        pkg-config
        cmake
        clang
      ]
    );
  };
}
