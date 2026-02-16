# My phone. Claude Code on the go.
# Build with: nix-on-droid switch --flake .#droid
{ pkgs, pkgs-unstable, lib, ... }:

{
  system.stateVersion = "24.05";

  user.shell = "${pkgs.fish}/bin/fish";

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

    # nix
    nix-output-monitor

    # system
    htop

    # node (for claude code)
    nodejs
  ];

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  home-manager = {
    useGlobalPkgs = true;

    config = { pkgs, lib, ... }: {
      home.stateVersion = "24.05";

      home.sessionVariables = {
        EDITOR = "nvim";
        XDG_CONFIG_HOME = "$HOME/.config";
        XDG_DATA_HOME = "$HOME/.local/share";
      };

      home.sessionPath = [
        "$HOME/.local/bin"
        "$HOME/.npm-global/bin"
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
          fish_add_path $HOME/.local/bin
          fish_add_path $HOME/.npm-global/bin

          set -gx EDITOR nvim
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

      home.activation.installClaude = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${pkgs.nodejs}/bin:$PATH"
        export NPM_CONFIG_PREFIX="$HOME/.npm-global"
        mkdir -p "$HOME/.npm-global"
        if ! command -v claude &> /dev/null && ! test -f "$HOME/.npm-global/bin/claude"; then
          echo "Installing Claude Code..."
          ${pkgs.nodejs}/bin/npm install -g @anthropic-ai/claude-code || echo "Claude Code install failed -- run manually"
        fi
      '';
    };
  };
}
