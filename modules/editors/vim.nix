# -*- mode: nix -*-
# modules/editors/vim.nix
# Neovim with sensible TUI defaults — default editor for chores (git, sudoedit, etc.).
#
# Usage:
#   imports = [ ../modules/editors/vim.nix ];
#   modules.editors.vim.enable = true;
#
# GUI Emacs stays available via `e` / Doom; this module owns EDITOR/VISUAL.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.editors.vim;
in {
  options.modules.editors.vim = {
    enable = mkEnableOption "Neovim with sensible defaults (TUI default editor)";
  };

  config = mkIf cfg.enable {
    # System-wide for tools that do not read home-manager session vars.
    environment.variables = {
      EDITOR = mkForce "nvim";
      VISUAL = mkForce "nvim";
    };

    # Ensure nvim is on the system PATH even outside HM-managed shells.
    environment.systemPackages = with pkgs; [
      neovim
      ripgrep
      fd
    ];

    home-manager.users.nicho = {
      home.packages = with pkgs; [
        ripgrep
        fd
      ];

      home.sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };

      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        vimdiffAlias = true;
        withNodeJs = false;
        withPython3 = true;

        plugins = with pkgs.vimPlugins; [
          # Syntax / structure
          {
            plugin = nvim-treesitter.withPlugins (p: [
              p.bash
              p.c
              p.json
              p.lua
              p.markdown
              p.markdown_inline
              p.nix
              p.python
              p.rust
              p.toml
              p.vim
              p.vimdoc
              p.yaml
            ]);
            type = "lua";
            config = ''
              require("nvim-treesitter.configs").setup({
                highlight = { enable = true },
                indent = { enable = true },
                -- Grammars are provided by Nix; do not auto-install.
                auto_install = false,
              })
            '';
          }

          # Fuzzy find (needs ripgrep + fd on PATH)
          plenary-nvim
          {
            plugin = telescope-nvim;
            type = "lua";
            config = ''
              local telescope = require("telescope")
              local builtin = require("telescope.builtin")
              telescope.setup({
                defaults = {
                  mappings = {
                    i = {
                      ["<C-j>"] = "move_selection_next",
                      ["<C-k>"] = "move_selection_previous",
                    },
                  },
                },
              })
              vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
              vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
              vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
              vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
              vim.keymap.set("n", "<leader>/", builtin.current_buffer_fuzzy_find, { desc = "Buffer search" })
            '';
          }

          {
            plugin = gitsigns-nvim;
            type = "lua";
            config = ''
              require("gitsigns").setup({
                signs = {
                  add = { text = "+" },
                  change = { text = "~" },
                  delete = { text = "_" },
                  topdelete = { text = "‾" },
                  changedelete = { text = "~" },
                },
              })
            '';
          }

          {
            plugin = comment-nvim;
            type = "lua";
            config = ''
              require("Comment").setup()
            '';
          }
        ];

        extraLuaConfig = ''
          -- Leader
          vim.g.mapleader = " "
          vim.g.maplocalleader = " "

          local opt = vim.opt

          -- UI
          opt.number = true
          opt.relativenumber = true
          opt.signcolumn = "yes"
          opt.cursorline = true
          opt.termguicolors = true
          opt.scrolloff = 4
          opt.sidescrolloff = 8
          opt.laststatus = 2
          opt.showmode = true
          opt.list = true
          opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

          -- Editing
          opt.expandtab = true
          opt.shiftwidth = 2
          opt.tabstop = 2
          opt.softtabstop = 2
          opt.smartindent = true
          opt.wrap = false
          opt.breakindent = true

          -- Search
          opt.ignorecase = true
          opt.smartcase = true
          opt.incsearch = true
          opt.hlsearch = true

          -- Files / undo
          opt.swapfile = false
          opt.backup = false
          opt.undofile = true
          opt.undodir = vim.fn.stdpath("state") .. "/undo"
          vim.fn.mkdir(vim.o.undodir, "p")

          -- Splits / windows
          opt.splitright = true
          opt.splitbelow = true

          -- System
          opt.clipboard = "unnamedplus"
          opt.mouse = "a"
          opt.updatetime = 250
          opt.timeoutlen = 400
          opt.completeopt = "menu,menuone,noselect"

          -- Clear search highlight
          vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

          -- Buffers / windows
          vim.keymap.set("n", "[b", "<cmd>bprevious<CR>", { desc = "Prev buffer" })
          vim.keymap.set("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
          vim.keymap.set("n", "<leader>w", "<cmd>write<CR>", { desc = "Write" })
          vim.keymap.set("n", "<leader>q", "<cmd>quit<CR>", { desc = "Quit" })
          vim.keymap.set("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

          -- Move lines in visual mode
          vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
          vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

          -- Keep cursor centered when scrolling search
          vim.keymap.set("n", "n", "nzzzv")
          vim.keymap.set("n", "N", "Nzzzv")

          -- Simple netrw as file browser
          vim.g.netrw_banner = 0
          vim.g.netrw_liststyle = 3
          vim.keymap.set("n", "<leader>e", "<cmd>Explore<CR>", { desc = "File explorer" })

          -- Diagnose missing treesitter gracefully (no noise on clean installs)
          vim.g.loaded_node_provider = 0
        '';
      };
    };
  };
}
