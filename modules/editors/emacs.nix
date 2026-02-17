{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.editors.emacs;
  
  # Emacs package with native compilation and Wayland support
  emacsPkg = (pkgs.emacsPackagesFor pkgs.emacs-pgtk).emacsWithPackages
    (epkgs: with epkgs; [
      vterm                                # Terminal emulator (binary dependency)
      treesit-grammars.with-all-grammars   # Tree-sitter language grammars
    ]);
    
  # Doom Emacs dependencies organized by category and module
  doomDeps = with pkgs; [
    # Core dependencies
    git
    ripgrep           # Core doom dependency
    fd                # Faster projectile indexing
    findutils         # File utilities
    gnutls            # SSL/TLS for package downloads
    
    # Build tools (for native-comp and packages)
    binutils          # For native compilation
    cmake
    gnumake
    
    # Font management
    fontconfig
    
    # :completion (company, ivy)
    # No additional system packages needed
    
    # :ui
    # No additional system packages needed
    
    # :editor
    editorconfig-core-c    # :tools editorconfig
    
    # :tools docker
    docker-compose
    hadolint               # Dockerfile linter
    # dockfmt is not in nixpkgs - optional Dockerfile formatter
    
    # :tools lookup
    sqlite                 # For lookup & org-roam database
    
    # :tools lsp
    # Language servers are included in :lang sections below
    
    # :tools tree-sitter
    # Covered by treesit-grammars in emacsWithPackages
    
    # :email mu4e
    mu                     # Email indexer/searcher
    isync                  # Provides mbsync for IMAP sync
    offlineimap            # Alternative email sync
    
    # :lang cc
    clang-tools            # clangd LSP, clang-format, clang-tidy
    
    # :lang clojure
    clojure
    clojure-lsp
    cljfmt                 # Clojure formatter
    
    # :lang common-lisp
    sbcl                   # Steel Bank Common Lisp
    
    # :lang csharp
    csharpier              # C# formatter
    omnisharp-roslyn       # C# LSP server
    
    # :lang go
    gopls                  # Go language server
    go-tools               # Go utilities (goimports, etc.)
    gore                   # Go REPL
    gomodifytags           # Manipulate struct tags
    gotests                # Generate tests
    
    # :lang json
    nodePackages.vscode-langservers-extracted  # Includes json-languageserver
    
    # :lang javascript
    nodejs                 # Required for many JS tools and copilot
    # vscode-langservers-extracted also provides eslint LSP
    
    # :lang lua
    lua-language-server
    
    # :lang markdown
    # No additional system packages needed (markdown-mode is pure elisp)
    
    # :lang nix
    nixfmt-classic         # Nix formatter
    nil                    # Nix language server
    
    # :lang ocaml
    ocamlPackages.ocamlformat    # OCaml formatter
    ocamlPackages.dune_3         # OCaml build system
    ocamlPackages.utop           # OCaml REPL
    ocamlPackages.ocp-indent     # OCaml indentation
    ocamlPackages.merlin         # OCaml completion/type info
    
    # :lang org
    pandoc                 # Document conversion for org exports
    graphviz               # Org-mode diagram rendering
    hugo                   # Static site generator (for ox-hugo, easy-hugo)
    
    # :lang python
    (python3.withPackages (ps: with ps; [
      black                # Python formatter
      pyflakes             # Python linter
      isort                # Python import sorter
      pipenv               # Python env manager
      pytest               # Python testing
    ]))
    pyenv                  # Python version manager
    python312Packages.python-lsp-server  # Python LSP
    
    # :lang rust
    rust-analyzer          # Rust language server
    rustc                  # Rust compiler
    cargo                  # Rust package manager
    
    # :lang sh
    shfmt                  # Shell script formatter
    shellcheck             # Shell script linter
    fish                   # Fish shell (for fish-mode and sh module)
    
    # :lang web
    nodePackages.stylelint        # CSS linter
    nodePackages.js-beautify      # JS/HTML/CSS formatter
    html-tidy                     # HTML formatter
    tailwindcss-language-server   # For lsp-tailwindcss package
    
    # :lang yaml
    yaml-language-server   # YAML LSP
    
    # Additional package dependencies
    # copilot.el requires nodejs (already included above)
    # caddyfile-mode - no additional deps needed
    # yuck-mode - no additional deps needed (eww already in system)
    # mastodon - needs gnutls and curl for API calls
    curl
    
    # Utilities
    jq                     # JSON processor
  ];
in {
  options.modules.editors.emacs = {
    enable = mkEnableOption "Doom Emacs with all dependencies";
    
    enableDaemon = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Emacs daemon service (systemd user service)";
    };
  };

  config = mkIf cfg.enable {
    # Note: emacs-overlay is now provided via flake.nix inputs

    # Install Emacs and all Doom dependencies
    environment.systemPackages = [ emacsPkg ] ++ doomDeps;
    
    # Environment variables for Doom Emacs
    # Use ${} syntax to ensure proper variable expansion at runtime
    environment.sessionVariables = {
      DOOMDIR = "\${HOME}/.config/doom";
      EMACSDIR = "\${HOME}/.config/emacs";
      # Set EDITOR based on daemon mode: emacsclient if daemon enabled, emacs otherwise
      EDITOR = if cfg.enableDaemon then "emacsclient -c" else "emacs";
      # Wayland-specific settings for emacs-pgtk
      MOZ_ENABLE_WAYLAND = "1";
    };
    
    # Add Doom's bin directory to PATH
    environment.sessionVariables.PATH = [ "\${HOME}/.config/emacs/bin" ];
    
    # Enable Emacs daemon as systemd user service
    # This starts Emacs server on login for faster client startup
    systemd.user.services.emacs = mkIf cfg.enableDaemon {
      description = "Emacs text editor daemon";
      documentation = [ "info:emacs" "man:emacs(1)" "https://gnu.org/software/emacs/" ];
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "default.target" ];
      
      serviceConfig = {
        Type = "forking";
        ExecStart = "${emacsPkg}/bin/emacs --daemon";
        ExecStop = "${emacsPkg}/bin/emacsclient --eval \"(kill-emacs)\"";
        Restart = "on-failure";
      };
    };
    
    # Ensure fonts for Doom are available
    fonts.packages = with pkgs; [
      emacs-all-the-icons-fonts
    ];
    
    # Doom Emacs configuration via home-manager
    home-manager.users.nicho = {
      # Activation script to clone Doom Emacs and create symlinks
      home.activation.doomSetup = ''
        export PATH="${emacsPkg}/bin:${pkgs.git}/bin:$PATH"
        # Clone Doom Emacs distribution if not already present
        if [ ! -d "$HOME/Code/nix/modules/editors/config/emacs" ]; then
          echo "Cloning Doom Emacs..."
          git clone --depth 1 https://github.com/doomemacs/doomemacs \
            $HOME/Code/nix/modules/editors/config/emacs
        fi
        # Symlink emacs and doom config to XDG config dir
        ln -sf $HOME/Code/nix/modules/editors/config/emacs $HOME/.config/emacs
        ln -sf $HOME/Code/nix/modules/editors/config/doom $HOME/.config/doom
        if [ ! -d "$HOME/.config/emacs/.local" ]; then
          echo "Installing Doom Emacs..."
          $HOME/.config/emacs/bin/doom install --no-config
        fi
      '';
    };
  };
}
