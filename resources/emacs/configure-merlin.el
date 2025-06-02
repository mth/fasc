; https://dev.to/erickgnavar/using-compilation-mode-to-run-all-the-things-231o

(setq dune-run-program-path nil)
(setq dune-run-program-terminal nil)

(defun rerun-program-in-dune-terminal ()
  "Rerun program using dune"
  (interactive)
  (if dune-run-program-path
    (let ((buffer (current-buffer))
	  (program-name (format "%s output" (car dune-run-program-path))))
      (if (and (string-equal (buffer-name buffer) (format "*%s*" program-name))
	       (not (term-check-proc buffer)))
	(term-exec buffer program-name dune-command nil
		   (list "exec" (cdr dune-run-program-path)))))))

(defun run-program-after-dune-compile (buffer desc)
  (if (and dune-run-program-path (string-equal (buffer-name buffer) "*compilation*"))
      (let ((program-name (car dune-run-program-path))
	    (program-path (cdr dune-run-program-path)))
	(setq dune-run-program-path nil)
	(if (equal (string-trim desc) "finished")
	    (let ((program-terminal (alist-get program-name dune-run-program-terminal)))
	      (if program-terminal
		  (ignore-errors (delete-process program-terminal)))
	      (setq program-terminal
		    (make-term (format "%s output" program-name)
			       dune-command nil "exec" program-path))
	      (setq dune-run-program-terminal
		    (cons (cons program-name program-terminal)
			  (assoc-delete-all program-name dune-run-program-terminal)))
	      (set-buffer program-terminal)
	      (term-char-mode)
	      (setq-local dune-run-program-path (cons program-name program-path))
	      (dune-run-program-mode)
	      (pop-to-buffer-same-window program-terminal))))))

(defun dune-run-program ()
  "Run program using dune"
  (interactive)
  (require 'dune)

  (let* ((buffer-name (file-name-base (buffer-file-name)))
	 (dune-describe (shell-command-to-string (format "%s describe" dune-command)))
	 (description (if (string-prefix-p "(" dune-describe) (read dune-describe)))
	 (target (cadr (assoc 'build_context description)))
	 (executables (cadr (assoc 'executables description)))
         (names (cadr (assoc 'names executables)))
         (name (car (append
		     (cl-loop for name in names
			      if (string-equal-ignore-case (symbol-name name) buffer-name)
			      collect name)
		     names '(nil)))))
    (if name
	(progn
	  (setq dune-run-program-path (cons name (format "%S/%S.exe" target name)))
          (compile (format "%s build" dune-command)))
      (if (file-exists-p "dune")
	  (message "Couldn't determine from dune configuration")
	(if (= (map-y-or-n-p "Dune %s file missing, create it? " 'ignore '(build)) 1)
	    (let ((dune-buffer (find-file-noselect "dune")))
	      (if (= (buffer-size dune-buffer) 0)
		  (with-current-buffer dune-buffer
		    (insert (format "(executables\n  %S\n" `(names ,buffer-name)))
		    (insert "  ; (libraries graphics unix)\n  ; (libraries sdl2)\n")
		    (insert "  ; (link_flags \"-cclib\" \"-lSDL2\")\n  )\n")
		    (prin1 '(env (dev (flags (:standard -warn-error -a)))) dune-buffer)
		    (save-buffer)))
	      (if (not (file-exists-p "dune-project"))
	        (with-temp-buffer
		  (insert "(lang dune 3.0)")
		  (write-file "dune-project")))
	      (dune-run-program)))))))

(define-minor-mode dune-run-program-mode
		   "Minor mode for dune-run-program key bindings"
		   :init-value nil
		   :keymap `((,(kbd "<f5>") . rerun-program-in-dune-terminal)))

(defun bind-ocaml-keys ()
  (local-set-key (kbd "<f5>") #'dune-run-program))

(setq merlin-command nil)
(if (file-executable-p "/usr/bin/ocamlmerlin")
    (setq merlin-command "/usr/bin/ocamlmerlin")
  (let ((opam-share (ignore-errors (car (process-lines "opam" "var" "share")))))
    (when (and opam-share (file-directory-p opam-share))
      ;; Register Merlin
      (add-to-list 'load-path (expand-file-name "emacs/site-lisp" opam-share))
      ;; Use opam switch to lookup ocamlmerlin binary
      (setq merlin-command 'opam)
      ;; To easily change opam switches within a given Emacs session, you can
      ;; install the minor mode https://github.com/ProofGeneral/opam-switch-mode
      ;; and use one of its "OPSW" menus.
      )))
(when merlin-command
  (autoload 'merlin-mode "merlin" nil t nil)
  ;; Automatically start it in OCaml buffers
  (add-hook 'tuareg-mode-hook 'merlin-mode t)
  (add-hook 'caml-mode-hook 'merlin-mode t))

(add-hook 'merlin-mode-hook 'company-mode)

(require 'merlin-eldoc)
(add-hook 'tuareg-mode-hook 'merlin-eldoc-setup)
(add-hook 'tuareg-mode-hook 'bind-ocaml-keys)
(add-hook 'compilation-finish-functions 'run-program-after-dune-compile)

(setq tuareg-indent-align-with-first-arg t)
(setq tuareg-match-patterns-aligned t)
(setq tuareg-in-indent 0)

(provide 'configure-merlin)
