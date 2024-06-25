(global-tab-line-mode) ; show buffer tabs

(add-hook 'after-init-hook 'global-company-mode)
(setq company-idle-delay 0.5)          ; Smaller delay in showing suggestion
(setq company-minimum-prefix-length 2) ; Show suggestions after 2 characters
(setq company-selection-wrap-around t) ; From end of suggestions to start
(company-tng-configure-default)        ; Use tab key to cycle through suggestions 

(add-hook 'emacs-lisp-mode-hook 'eldoc-mode)
(add-hook 'lisp-interaction-mode-hook 'eldoc-mode)
(add-hook 'ielm-mode-hook 'eldoc-mode)

(provide 'configure-company)
