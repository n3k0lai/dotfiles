{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.fcitx5;
  theme = config.modules.desktop.theme;
  devMode = config.modules.core.devMode;
in {
  options.modules.desktop.fcitx5 = {
    enable = mkEnableOption "fcitx5 input method";
  };

  config = mkIf cfg.enable {
    # Input method configuration
    i18n.inputMethod = {
      type = "fcitx5";
      enable = true;
      fcitx5.addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-mozc
        fcitx5-gtk
        kdePackages.fcitx5-qt
        fcitx5-rime
      ];
    };

    home-manager.users.nicho = { config, ... }:
    let
      mkFileSource = relativePath: storeSource:
        if devMode.enable
        then config.lib.file.mkOutOfStoreSymlink "${devMode.repoPath}/${relativePath}"
        else storeSource;
    in {
      # Symlink individual fcitx5 config files (not the whole dir — fcitx5 writes to profile at runtime)
      xdg.configFile."fcitx5/config".source =
        mkFileSource "modules/desktop/config/fcitx5/config" ./config/fcitx5/config;
      xdg.configFile."fcitx5/conf/classicui.conf".source =
        mkFileSource "modules/desktop/config/fcitx5/conf/classicui.conf" ./config/fcitx5/conf/classicui.conf;
      xdg.configFile."fcitx5/conf/unicode.conf".source =
        mkFileSource "modules/desktop/config/fcitx5/conf/unicode.conf" ./config/fcitx5/conf/unicode.conf;
      xdg.configFile."fcitx5/conf/pinyin.conf".source =
        mkFileSource "modules/desktop/config/fcitx5/conf/pinyin.conf" ./config/fcitx5/conf/pinyin.conf;

      # fcitx5 profile is not managed by home-manager — fcitx5 rewrites it at runtime.
      # It creates a default profile on first launch automatically.

      # Generate fcitx5 ClassicUI theme from active theme colors
      xdg.dataFile."fcitx5/themes/nixos-theme/theme.conf".text = ''
        [Metadata]
        Name=nixos-theme
        Version=1
        Author=NixOS Config
        Description=Auto-generated from ${theme.name} theme

        [InputPanel]
        NormalColor=#${theme.colors.foreground}
        HighlightCandidateColor=#${theme.colors.background}
        HighlightColor=#${theme.colors.foreground}
        HighlightBackgroundColor=#${theme.colors.accent}

        [InputPanel/Background]
        Color=#${theme.colors.background}
        BorderColor=#${theme.colors.borderFocused}
        BorderWidth=2

        [InputPanel/Background/Margin]
        Left=10
        Right=10
        Top=8
        Bottom=8

        [InputPanel/ContentMargin]
        Left=8
        Right=8
        Top=8
        Bottom=8

        [InputPanel/TextMargin]
        Left=5
        Right=5
        Top=5
        Bottom=5

        [InputPanel/Highlight]
        Color=#${theme.colors.accent}

        [InputPanel/Highlight/Margin]
        Left=5
        Right=5
        Top=3
        Bottom=3

        [Menu]
        NormalColor=#${theme.colors.foreground}
        HighlightColor=#${theme.colors.background}
        HighlightBackgroundColor=#${theme.colors.accent}
        Separator=#${theme.colors.border}

        [Menu/Background]
        Color=#${theme.colors.background}
        BorderColor=#${theme.colors.border}
        BorderWidth=2

        [Menu/Background/Margin]
        Left=2
        Right=2
        Top=2
        Bottom=2

        [Menu/ContentMargin]
        Left=5
        Right=5
        Top=5
        Bottom=5

        [Menu/Highlight]
        Color=#${theme.colors.accent}

        [Menu/Highlight/Margin]
        Left=5
        Right=5
        Top=3
        Bottom=3

        [Menu/Separator]
        Color=#${theme.colors.border}
      '';
    };
  };
}
