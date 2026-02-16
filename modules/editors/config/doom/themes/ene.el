;;; doom-ene-theme.el --- twitch-influenced, blue-centric colorscheme -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Added: January 22, 2024
;; Author: Nicholai <https://github.com/n3k0lai>
;; Maintainer:
;; Source:
;;
;;; Commentary:
;;; Code:

(require 'doom-themes)


;;
;;; Variables

(defgroup doom-ene-theme nil
  "Options for doom-ene."
  :group 'doom-themes)

(defcustom doom-ene-brighter-comments nil
  "If non-nil, comments will be highlighted in more vivid colors."
  :group 'doom-ene-theme
  :type 'boolean)

(defcustom doom-ene-comment-bg doom-ene-brighter-comments
  "If non-nil, comments will have a subtle, darker background. Enhancing their
legibility."
  :group 'doom-ene-theme
  :type 'boolean)

(defcustom doom-ene-padded-modeline doom-themes-padded-modeline
  "If non-nil, adds a 4px padding to the mode-line. Can be an integer to
determine the exact padding."
  :group 'doom-ene-theme
  :type '(choice integer boolean))


;;
;;; Theme definition

(def-doom-theme doom-ene
  "The best helper :>"

  ;; name        gui       256       16
  ((bg         '("#191919" nil       nil          ))
   (bg-alt     '("#3F3F3F" nil       nil          ))
   (base0      '("#1B2229" "black"   "black"      ))
   (base1      '("#161613" "#101010" "brightblack"))
   (base2      '("#1D1F20" "#191919" "brightblack"))
   (base3      '("#2D2E2E" "#252525" "brightblack"))
   (base4      '("#4E4E4E" "#454545" "brightblack"))
   (base5      '("#555556" "#6B6B6B" "brightblack"))
   (base6      '("#767679" "#7B7B7B" "brightblack"))
   (base7      '("#CFC0C5" "#C1C1C1" "brightblack"))
   (base8      '("#FFFFFF" "#FFFFFF" "brightwhite"))
   (fg         '("#FEF3E9" "#DFDFDF" "brightwhite"))
   (fg-alt     '("#556172" "#4D4D4D" "white"))

   (grey       '("#D2D2E6" "#D2D2E6" "brightblack"))
   (red        '("#FA2828" "#FA2828" "red"))
   (orange     '("#FF6905" "#FF6905" "brightred"))
   (green      '("#00FA05" "#00FA05" "green"))
   (teal       '("#69FFC3" "#69FFC3" "teal"))
   (yellow     '("#FAFA19" "#FAFA19" "yellow"))
   (blue       '("#83D9F7" "#83D9F7" "brightblue"))
   (dark-blue  '("#6F95FC" "#6F95FC" "blue"))
   (magenta    '("#41145F" "#41145F" "magenta"))
   (violet     '("#8205B4" "#8205B4" "brightmagenta"))
   (cyan       '("#ADF0E7" "#ADF0E7" "brightcyan"))
   (dark-cyan  '("#39928D" "#39928D" "cyan"))

   ;; face categories
   (highlight      orange)
   (vertical-bar   (doom-lighten bg 0.1))
   (selection      base5)
   (builtin        orange)
   (comments       (if doom-ene-brighter-comments violet base5))
   (doc-comments   (if doom-ene-brighter-comments (doom-lighten violet 0.1) (doom-lighten base5 0.25)))
   (constants      violet)
   (functions      green)
   (keywords       magenta)
   (methods        green)
   (operators      magenta)
   (type           cyan)
   (strings        yellow)
   (variables      fg)
   (numbers        violet)
   (region         base4)
   (error          red)
   (warning        yellow)
   (success        green)
   (vc-modified    cyan)
   (vc-added       (doom-darken green 0.15))
   (vc-deleted     red)

   ;; custom categories
   (hidden     `(,(car bg) "black" "black"))
   (-modeline-pad
    (when doom-ene-padded-modeline
      (if (integerp doom-ene-padded-modeline) doom-ene-padded-modeline 4)))

   (modeline-fg 'unspecified)
   (modeline-fg-alt base4)

   (modeline-bg base1)
   (modeline-bg-inactive (doom-darken base2 0.2))

   (org-quote `(,(doom-lighten (car bg) 0.05) "#1f1f1f")))


  ;;;; Base theme face overrides
  ((cursor :background magenta)
   ((font-lock-comment-face &override) :slant 'italic)
   ((font-lock-type-face &override) :slant 'italic)
   (lazy-highlight :background violet :foreground base0 :distant-foreground base0 :bold bold)
   ((line-number &override) :foreground base5 :distant-foreground nil)
   ((line-number-current-line &override) :foreground base7 :distant-foreground nil)
   (mode-line
    :background modeline-bg :foreground modeline-fg
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color modeline-bg)))
   (mode-line-inactive
    :background modeline-bg-inactive :foreground modeline-fg-alt
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color modeline-bg-inactive)))

   ;;;; centaur-tabs
   (centaur-tabs-selected-modified :inherit 'centaur-tabs-selected
                                   :background bg
                                   :foreground yellow)
   (centaur-tabs-unselected-modified :inherit 'centaur-tabs-unselected
                                     :background bg-alt
                                     :foreground yellow)
   (centaur-tabs-active-bar-face :background yellow)
   (centaur-tabs-modified-marker-selected :inherit 'centaur-tabs-selected :foreground fg)
   (centaur-tabs-modified-marker-unselected :inherit 'centaur-tabs-unselected :foreground fg)
   ;;;; css-mode <built-in> / scss-mode
   (css-proprietary-property :foreground keywords)
   ;;;; doom-modeline
   (doom-modeline-bar :background yellow)
   (doom-modeline-buffer-file :inherit 'mode-line-buffer-id :weight 'bold)
   (doom-modeline-buffer-path :inherit 'bold :foreground green)
   (doom-modeline-buffer-project-root :foreground green :weight 'bold)
   (doom-modeline-buffer-modified :inherit 'bold :foreground orange)


   (isearch :foreground base0 :background green)
   ;;;; ediff <built-in>
   (ediff-fine-diff-A :background (doom-blend magenta bg 0.3) :weight 'bold)
   ;;;; evil
   (evil-search-highlight-persist-highlight-face :background violet)
   ;;;; evil-snipe
   (evil-snipe-first-match-face :foreground base0 :background green)
   (evil-snipe-matches-face     :foreground green :underline t)
   ;;;; flycheck
   (flycheck-error   :underline `(:style wave :color ,red)    :background base3)
   (flycheck-warning :underline `(:style wave :color ,yellow) :background base3)
   (flycheck-info    :underline `(:style wave :color ,green)  :background base3)
   ;;;; helm
   (helm-swoop-target-line-face :foreground magenta :inverse-video t)
   ;;;; ivy
   (ivy-current-match :background base3)
   (ivy-minibuffer-match-face-1 :background base1 :foreground base4)
   ;;;; markdown-mode
   (markdown-blockquote-face :inherit 'italic :foreground dark-blue)
   (markdown-list-face :foreground magenta)
   (markdown-pre-face  :foreground cyan)
   (markdown-link-face :inherit 'bold :foreground blue)
   ((markdown-code-face &override) :background (doom-lighten base2 0.045))
   ;;;; neotree
   (neo-dir-link-face   :foreground cyan)
   (neo-expand-btn-face :foreground magenta)
   ;;;; outline <built-in>
   ((outline-1 &override) :foreground magenta)
   ((outline-2 &override) :foreground orange)
   ;;;; org <built-in>
   (org-ellipsis :foreground orange)
   (org-tag :foreground yellow :bold nil)
   ((org-quote &override) :inherit 'italic :foreground base7 :background org-quote)
   (org-todo :foreground yellow :bold 'inherit)
   (org-list-dt :foreground yellow)
   ;;;; rainbow-delimiters
   (rainbow-delimiters-depth-1-face :foreground magenta)
   (rainbow-delimiters-depth-2-face :foreground orange)
   (rainbow-delimiters-depth-3-face :foreground green)
   (rainbow-delimiters-depth-4-face :foreground cyan)
   (rainbow-delimiters-depth-5-face :foreground magenta)
   (rainbow-delimiters-depth-6-face :foreground orange)
   (rainbow-delimiters-depth-7-face :foreground green))

  ;;;; Base theme variable overrides
  ;; ()
  )

;;; ene.el ends here
