(global-tab-line-mode) ; show buffer tabs

(cua-mode t) ; Ctrl-XCV for cut, copy and paste
(setq cua-auto-tabify-rectangles nil) ; Don't tabify after rectangle commands
(transient-mark-mode 1) ; standard selection-highlighting

(global-set-key (kbd "C-s") #'save-buffer)
(global-set-key (kbd "C-f") #'isearch-forward)
(define-key isearch-mode-map (kbd "C-f") #'isearch-repeat-forward)
(global-set-key (kbd "C-w") #'kill-buffer)
(global-set-key (kbd "C-o") #'find-file)
(global-set-key (kbd "C-z") #'undo)
(global-set-key (kbd "C-y") #'undo-redo)

(provide 'configure-cua)
