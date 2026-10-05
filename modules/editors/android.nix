{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.editors.android;
  buildToolsVersion = "34.0.0";
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformToolsVersion = "36.0.2";
    buildToolsVersions = [ buildToolsVersion ];
    platformVersions = [ "34" ];
    includeNDK = true;
    ndkVersions = [ "26.1.10909125" ];
    cmakeVersions = [ "3.22.1" ];
  };
  androidSdk = androidComposition.androidsdk;
in {
  options.modules.editors.android = {
    enable = mkEnableOption "Android development environment";
  };

  config = mkIf cfg.enable {
    nixpkgs.config.android_sdk.accept_license = true;

    environment.systemPackages = with pkgs; [
      android-studio
      android-tools
      androidSdk
      jdk17
      # Android Studio needs these to open browser for Google sign-in on Wayland
      xdg-utils
      glib # provides gsettings
    ];

    # programs.adb was removed in 26.05. systemd 258 writes the uaccess
    # rules. android-tools is the adb command.
    users.users.nicho.extraGroups = [ "adbusers" "kvm" ];

    # KVM for Android emulator hardware acceleration
    virtualisation.libvirtd.enable = true;
    boot.kernelModules = [ "kvm-amd" ];

    environment.variables = {
      ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
      ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
      GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdk}/libexec/android-sdk/build-tools/${buildToolsVersion}/aapt2";
    };
  };
}
