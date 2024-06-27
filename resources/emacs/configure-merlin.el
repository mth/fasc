(defun dune-run-program ()
  "Run program using dune"
  (interactive)
  (require 'dune)

  (let* ((buffer-name (file-name-base (buffer-file-name)))
         (description (read (shell-command-to-string
			     (format "%s describe" dune-command))))
	 (target (cadr (assoc 'build_context description)))
	 (executables (cadr (assoc 'executables description)))
         (names (cadr (assoc 'names executables)))
         (name (car (append
		     (cl-loop for name in names
			      if (string-equal-ignore-case (symbol-name name) buffer-name)
			      collect name)
		     names '(nil)))))
    (if name
        (compile (format "%s exec %S/%S.exe" dune-command target name))
      (message "Couldn't determine from dune configuration"))))

(defun bind-ocaml-keys ()
  (local-set-key (kbd "<f5>") #'dune-run-program))  

(let ((opam-share (ignore-errors (car (process-lines "opam" "var" "share")))))
 (when (and opam-share (file-directory-p opam-share))
  ;; Register Merlin
  (add-to-list 'load-path (expand-file-name "emacs/site-lisp" opam-share))
  (autoload 'merlin-mode "merlin" nil t nil)
  ;; Automatically start it in OCaml buffers
  (add-hook 'tuareg-mode-hook 'merlin-mode t)
  (add-hook 'caml-mode-hook 'merlin-mode t)
  ;; Use opam switch to lookup ocamlmerlin binary
  (setq merlin-command 'opam)
  ;; To easily change opam switches within a given Emacs session, you can
  ;; install the minor mode https://github.com/ProofGeneral/opam-switch-mode
  ;; and use one of its "OPSW" menus.
  ))

(add-hook 'merlin-mode-hook 'company-mode)

(require 'merlin-eldoc)
(add-hook 'tuareg-mode-hook 'merlin-eldoc-setup)
(add-hook 'tuareg-mode-hook 'bind-ocaml-keys)

(provide 'configure-merlin)
