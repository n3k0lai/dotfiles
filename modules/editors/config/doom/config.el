;;; config.el -*- lexical-binding: t; -*-

(setq user-full-name "Nicholai"
      user-mail-address "nicholai@comfy.sh"
      command-line-default-directory "~/"        ; set default directory to home
      +doom-dashboard-pwd-policy "~/"
      default-directory "~/"
      undo-limit 80000000                        ; raise undo-limit to 80mb
      evil-want-fine-undo t                      ; by default, while in =insert= all changes are one big blob. Be more granular
      auto-save-default t                        ; I have lost too much code to not have this enabled
      which-key-idle-delay 0.3                   ; be pushier with suggestions
      which-key-idle-secondary-delay 0
      shell-file-name (executable-find "sh")     ; sh for shpeed
      vterm-shell (executable-find "fish")       ; use fish in vterm ~>
      explicit-shell-file-name (executable-find "fish")
      mastodon-instance-url "https://emacs.ch"
      mastodon-active-user "n3k0lai")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-dracula)
                                        ;(setq doom-theme 'doom-ene)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/Org/")

(after! org
  (setq
   org-todo-keywords
   `((sequence "TODO(t)" "PROJ(p)" "LOOP(r)" "STRT(s)" "WAIT(w)" "HOLD(h)" "IDEA(i)" "|" "DONE(d)" "KILL(k)")
     (sequence "[ ](T)" "[-](S)" "[?](W)" "|" "[X](D)")
     (sequence "|" "OKAY(o)" "YES(y)" "NO(n)")
     (sequence "EXHALE" "INHALE" "BREATH" "|")
     (sequence "|" "WATER BREAK"))
   org-todo-keyword-faces
   `(("INHALE"  . ,(doom-color 'green))
     ("EXHALE"  . "#FA2828")
     ("BREATH"   . "#979797")
     ("WATER BREAK" . "#1E69FF")
     ("TODO"  . ,(doom-color 'orange))
     ("HACK"  . ,(doom-color 'orange))
     ("TEMP"  . ,(doom-color 'orange))
     ("DONE"  . ,(doom-color 'green))
     ("NOTE"  . ,(doom-color 'green))
     ("DONT"  . ,(doom-color 'red))
     ("DEBUG"  . ,(doom-color 'red))
     ("FAIL"  . ,(doom-color 'red))
     ("FIXME" . ,(doom-color 'red))
     ("XXX"   . ,(doom-color 'blue))
     ("XXXX"  . ,(doom-color 'blue))))
  (super-save-mode +1))

(after! projectile
  (setq projectile-project-root-files-bottom-up '("package.json" ".projectile" ".project" ".git")
        projectile-project-search-path '("~/.doom.d" "~/Code" "~/Org" "~/Code/dotfiles" "~/Code/n3k0lai.github.io" "~/Code/ene" "~/Code/golf"))
  (setq projectile-project-root-files-bottom-up (remove ".git"
                                                        projectile-project-root-files-bottom-up)))

;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
