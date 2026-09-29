# Phone terminal. CLI only.
# Build with: nix-on-droid switch --flake .#droid
{ pkgs, pkgs-unstable, lib, ... }:

{
  system.stateVersion = "24.05";

  # Same zone as kiss. No desktop session on this host.
  time.timeZone = "America/New_York";

  user.shell = "${pkgs.fish}/bin/fish";

  # Keep a pre-existing /etc file out of the way instead of aborting activation.
  environment.etcBackupExtension = ".bak";

  environment.packages = with pkgs; [
    # core
    git
    openssh
    gnupg

    # shell
    fish
    tmux

    # editors
    neovim

    # search
    ripgrep
    fd
    fzf
    tree

    # data
    jq
    curl
    wget

    # text tools the bootstrap shell had, and a terminal expects
    gnugrep
    gnused
    gawk
    findutils
    diffutils

    # archives (same CLI set as users/nicho.nix)
    zip
    unzip
    gnutar
    gzip
    xz

    # nix
    nix-output-monitor

    # system
    htop

    # mosh client (for connecting to ene/rook from the phone)
    mosh
  ];

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-bak";

    config = { pkgs, lib, ... }: {
      home.stateVersion = "24.05";

      home.sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
        XDG_CONFIG_HOME = "$HOME/.config";
        XDG_DATA_HOME = "$HOME/.local/share";
      };

      home.sessionPath = [
        "$HOME/.grok/bin"
        "$HOME/.local/bin"
      ];

      programs.git = {
        enable = true;
        userName = "n3k0lai";
        userEmail = "nicholai@comfy.sh";
        extraConfig = {
          init.defaultBranch = "master";
          pull.rebase = true;
          url."git@github.com:".insteadOf = "https://github.com/";
        };
      };

      programs.fish = {
        enable = true;
        shellInit = ''
          # fish_add_path prepends, so the last call is the front of PATH.
          fish_add_path $HOME/.local/bin
          # Real grok binary. The kiss fish function wraps grok-update and is desktop-only.
          fish_add_path $HOME/.grok/bin

          set -gx EDITOR nvim
          set -gx VISUAL nvim
          set -gx XDG_CONFIG_HOME "$HOME/.config"
          set -gx XDG_DATA_HOME "$HOME/.local/share"
        '';

        interactiveShellInit = ''
          # colorscheme (waves)
          set -gx foreground fef3e9
          set -gx background 191919
          set -gx color0 191919
          set -gx color8 3f3f3f
          set -gx color3 af9976
          set -gx color11 ffe8c5
          set -gx color4 6495fc
          set -gx color12 83d9f7
          set -gx color6 39928d
          set -gx color14 adf0e7
          set -gx color15 fef3e9
        '';

        functions = {
          fish_prompt = ''
            set -l suffix '>'
            if functions -q fish_is_root_user; and fish_is_root_user
                set suffix '#'
            end
            echo -n -s (set_color blue) '鱼 ' (set_color brblue) (prompt_pwd) $suffix " "
          '';

          fish_greeting = ''
            echo "droid"
          '';

          vim = "nvim $argv";
          v = "nvim $argv";
          ls = "command ls -hN --color=auto --group-directories-first $argv";
        };
      };

      programs.ssh = {
        enable = true;
        matchBlocks = {
          "github.com" = {
            hostname = "github.com";
            identityFile = "~/.ssh/id_ed25519";
            identitiesOnly = true;
          };
        };
      };

      programs.tmux = {
        enable = true;
        prefix = "C-a";
        mouse = true;
        baseIndex = 1;
        keyMode = "vi";
        extraConfig = ''
          bind | split-window -h
          bind - split-window -v
          set -g status-position bottom
          set -g status-justify left
          set -g status-style 'bg=colour0 fg=colour7'
        '';
      };

    };
  };
}
