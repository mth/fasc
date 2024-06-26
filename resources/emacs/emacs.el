(add-to-list 'load-path "~/.local/emacs-lisp")
(setq inhibit-splash-screen t) ; Don't show splash screen at startup
(setq make-backup-files nil)   ; Don't create foo~ files
(require 'configure-cua)
(require 'configure-company)
(require 'configure-merlin)
; (require 'configure-utop)
