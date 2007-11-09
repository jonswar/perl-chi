(setq chi-root (concat home "/chi"))
(setq chi-t-dir (concat chi-root "/t"))
(setq chi-lib-dir (concat chi-root "/lib"))
(setq chitest-binary (concat chi-root "/bin/chitest"))

(defun test-script-for-module (module)
  (concat chi-t-dir "/" (test-pattern-for-module module) ".t")
  )

(defun test-pattern-for-module (module)
  (replace-regexp-in-string
   "::" "-"
   (replace-regexp-in-string "CHI::t::" "" module))
  )

(defun chic ()
  "Run bin/chitest for the current test class in a compile buffer; use C-x C-n to cycle through errors"
  (interactive)
  (let ((test-pattern (test-pattern-for-module (module-name-for-perl-file))))
    (setq compile-command (concat chitest-binary " -c " test-pattern)))
  (call-interactively 'compile))
(defun chid ()
  "Run current test class in a perl debug buffer, and breakpoint at start of first test subroutine"
  (interactive)
  (let* ((module (module-name-for-perl-file))
         (test-script (test-script-for-module module))
         (hist-sym (gud-symbol 'history nil 'perldb))
         (gud-buffer-name (concat "*gud-" (test-pattern-for-module module) ".t*")))
    (unless (boundp hist-sym) (set hist-sym nil))
    (let ((last-cmd (car-safe (symbol-value hist-sym))))
      (unless (and last-cmd (string-match (concat "perl -I" chi-lib-dir " -d " test-script) last-cmd))
        (push (concat "perl -I" chi-lib-dir " -d " test-script " ") gud-perldb-history)))
    (call-interactively 'perldb)
    (set-buffer gud-buffer-name)
    (gud-call (concat "source " home "/shell/.perl5db/chitest.rc"))))

(defun chim ()
  "Run bin/chitest for the current method in the current test class in a compile buffer; use C-x C-n to cycle through errors"
  (interactive)
  (let ((test-pattern (test-pattern-for-module (module-name-for-perl-file)))
        (method (current-perl-subroutine)))
    (cond (method
           (setq compile-command (concat chitest-binary " -c '" test-pattern "' -m '^" method "$'"))
           (call-interactively 'compile))
          (t
           (message "could not determine current perl subroutine")))))
(defun chir ()
  "Repeat last compile command"
  (interactive)
  (compile compile-command))
(defun chit ()
  "Run bin/chitest in a compile buffer; use C-x C-n to cycle through errors"
  (interactive)
  (unless (and compile-command (string-match chitest-binary compile-command))
    (setq compile-command (concat chitest-binary " ")))
  (call-interactively 'compile))

(global-set-key "\C-c\C-c" 'chic)
(global-set-key "\C-c\C-d" 'chid)
(global-set-key "\C-c\C-m" 'chim)
(global-set-key "\C-c\C-r" 'chir)
(global-set-key "\C-c\C-t" 'chit)
