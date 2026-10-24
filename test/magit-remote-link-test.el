;;; magit-remote-link-test.el --- Tests for magit-remote-link -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -L <magit deps> -l test/magit-remote-link-test.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'magit-remote-link)

(ert-deftest mrl-parse-https-url ()
  (should (equal (mrl--parse-remote-url "https://github.com/pkulev/magit-remote-link.el.git")
                 '(:scheme "https" :host "github.com" :path "pkulev/magit-remote-link.el")))
  (should (equal (plist-get (mrl--parse-remote-url "http://example.org/a/b") :scheme) "http")))

(ert-deftest mrl-parse-ssh-urls ()
  (should (equal (mrl--parse-remote-url "git@github.com:me/foo.git")
                 '(:scheme "https" :host "github.com" :path "me/foo")))
  (should (equal (mrl--parse-remote-url "user@host.org:/srv/git/org-mode.git")
                 '(:scheme "https" :host "host.org" :path "srv/git/org-mode")))
  (should (equal (mrl--parse-remote-url "ssh://git@host.org:2222/a/b.git")
                 '(:scheme "https" :host "host.org" :path "a/b")))
  (should (equal (mrl--parse-remote-url "git+ssh://u@host.org/srv/git/org-mode.git")
                 '(:scheme "https" :host "host.org" :path "srv/git/org-mode"))))

(ert-deftest mrl-parse-unparseable-url ()
  (should-not (mrl--parse-remote-url "/local/path/repo.git")))

(ert-deftest mrl-format-github ()
  (should (equal (mrl-format-url "git@github.com:me/repo.git" "main" "src/a.el" 12 nil)
                 "https://github.com/me/repo/blob/main/src/a.el#L12"))
  (should (equal (mrl-format-url "https://github.com/me/repo.git" "main" "a.el" 12 20)
                 "https://github.com/me/repo/blob/main/a.el#L12-L20")))

(ert-deftest mrl-format-other-providers ()
  (should (equal (mrl-format-url "https://gitlab.com/me/repo.git" "main" "a.el" 3 5)
                 "https://gitlab.com/me/repo/-/blob/main/a.el#L3-5"))
  (should (equal (mrl-format-url "git@git.sr.ht:~me/repo" "main" "a.el" 3 nil)
                 "https://git.sr.ht/~me/repo/tree/main/item/a.el#L3"))
  (should (equal (mrl-format-url "https://codeberg.org/me/repo.git" "main" "a.el" 3 nil)
                 "https://codeberg.org/me/repo/src/branch/main/a.el#L3")))

(ert-deftest mrl-format-savannah-cgit ()
  (dolist (url '("https://git.savannah.nongnu.org/git/org-mode.git"
                 "git+ssh://user@git.savannah.nongnu.org/srv/git/org-mode.git"
                 "user@git.savannah.nongnu.org:/srv/git/org-mode.git"))
    (should (equal (mrl-format-url url "main" "lisp/org.el" 16105 nil)
                   "https://cgit.git.savannah.nongnu.org/cgit/org-mode.git/tree/lisp/org.el?h=main#n16105")))
  (should (equal (mrl-format-url "https://git.savannah.nongnu.org/git/org-mode.git"
                                 "main" "lisp/org.el" 10 20)
                 "https://cgit.git.savannah.nongnu.org/cgit/org-mode.git/tree/lisp/org.el?h=main#n10")))

(ert-deftest mrl-format-custom-host-rule ()
  (let ((magit-remote-link-hosts
         '(("\\`git\\.example\\.com/" cgit "https://web.example.com/cgit/%p"))))
    (should (equal (mrl-format-url "https://git.example.com/team/proj.git" "dev" "a.c" 1 nil)
                   "https://web.example.com/cgit/team/proj/tree/a.c?h=dev#n1"))))

(ert-deftest mrl-format-unknown-host-defaults-to-github-layout ()
  (should (equal (mrl-format-url "https://git.example.com/team/proj.git" "main" "a.c" 1 nil)
                 "https://git.example.com/team/proj/blob/main/a.c#L1")))

(ert-deftest mrl-format-explicit-overrides ()
  (should (equal (mrl-format-url "https://git.example.com/x.git" "main" "a.c" 1 nil
                                 'cgit "https://web.example.com/cgit/x.git/")
                 "https://web.example.com/cgit/x.git/tree/a.c?h=main#n1")))

(ert-deftest mrl-format-encodes-branch-and-file ()
  (should (equal (mrl-format-url "https://github.com/me/repo" "feat/x" "my dir/a b.el" 1 nil)
                 "https://github.com/me/repo/blob/feat/x/my%20dir/a%20b.el#L1")))

(ert-deftest mrl-format-errors ()
  (should-error (mrl-format-url "/local/repo" "main" "a" 1 nil) :type 'user-error)
  (should-error (mrl-format-url "https://github.com/a/b" "main" "a" 1 nil 'nonesuch)
                :type 'user-error))

(defmacro mrl-test-with-repo (&rest body)
  "Run BODY in a fresh repo on branch main with two commits and a file a.el.
`default-directory' is the repository root and the file is open in the
current buffer, with ten lines of text."
  (declare (indent 0))
  `(let ((default-directory (file-name-as-directory (make-temp-file "mrl-test" t))))
     (unwind-protect
         (progn
           (mrl-test-git "init" "-q" "-b" "main")
           (mrl-test-git "remote" "add" "origin" "git@github.com:me/repo.git")
           (with-temp-file "a.el" (dotimes (i 10) (insert (format "line %d\n" (1+ i)))))
           (mrl-test-git "add" "a.el")
           (mrl-test-git "commit" "-q" "-m" "one")
           (mrl-test-git "commit" "-q" "--allow-empty" "-m" "two")
           (with-current-buffer (find-file-noselect "a.el")
             (unwind-protect (progn ,@body)
               (set-buffer-modified-p nil)
               (kill-buffer))))
       (delete-directory default-directory t))))

(defun mrl-test-git (&rest args)
  "Run git with ARGS in `default-directory', failing the test on error."
  (should (zerop (apply #'process-file "git" nil nil nil
                        "-c" "user.name=T" "-c" "user.email=t@example.org" args))))

(defun mrl-test-url (&optional remote)
  "Return `mrl--current-url' as if REMOTE (default \"origin\") was chosen."
  (cl-letf (((symbol-function 'magit-read-remote) (lambda (&rest _) (or remote "origin"))))
    (mrl--current-url)))

(ert-deftest mrl-current-lines ()
  (mrl-test-with-repo
    (goto-char (point-min)) (forward-line 4)
    (should (equal (mrl--current-lines) '(5)))
    ;; The region's end is only included if it isn't at the start of a line.
    (set-mark (point))
    (forward-line 2)
    (should (equal (let ((transient-mark-mode t) (mark-active t)) (mrl--current-lines))
                   '(5 . 6)))
    (end-of-line)
    (should (equal (let ((transient-mark-mode t) (mark-active t)) (mrl--current-lines))
                   '(5 . 7)))
    ;; A one-line region is just a line.
    (set-mark (point))
    (beginning-of-line)
    (should (equal (let ((transient-mark-mode t) (mark-active t)) (mrl--current-lines))
                   '(7)))
    ;; Line numbers are absolute even when the buffer is narrowed.
    (widen) (goto-char (point-min)) (forward-line 2)
    (narrow-to-region (point) (point-max))
    (should (equal (mrl--current-lines) '(3)))))

(ert-deftest mrl-current-url ()
  (mrl-test-with-repo
    (goto-char (point-min)) (forward-line 2)
    (should (equal (mrl-test-url) "https://github.com/me/repo/blob/main/a.el#L3"))
    ;; A detached HEAD is linked by hash.
    (mrl-test-git "checkout" "-q" "--detach")
    (should (string-match-p "/blob/[0-9a-f]\\{40\\}/a\\.el#L3\\'" (mrl-test-url)))))

(ert-deftest mrl-current-url-git-config-overrides ()
  (mrl-test-with-repo
    (mrl-test-git "remote" "add" "web" "https://git.example.com/x/y.git")
    (should (equal (mrl-test-url "web") "https://git.example.com/x/y/blob/main/a.el#L1"))
    (mrl-test-git "config" "remote.web.magit-remote-link-provider" "cgit")
    (mrl-test-git "config" "remote.web.magit-remote-link-url" "https://web.example.com/cgit/y.git/")
    (should (equal (mrl-test-url "web")
                   "https://web.example.com/cgit/y.git/tree/a.el?h=main#n1"))))

(ert-deftest mrl-current-url-errors ()
  (mrl-test-with-repo
    (should-error (mrl-test-url "nonexistent") :type 'user-error))
  (mrl-test-with-repo
    (mrl-test-git "remote" "add" "local" "/some/local/path")
    (should-error (mrl-test-url "local") :type 'user-error))
  (with-temp-buffer
    (let ((default-directory temporary-file-directory))
      (should-error (mrl-test-url) :type 'user-error))))

(ert-deftest mrl-commands-use-current-url ()
  (mrl-test-with-repo
    (let (copied opened)
      (cl-letf (((symbol-function 'magit-read-remote) (lambda (&rest _) "origin"))
                ((symbol-function 'kill-new) (lambda (s) (setq copied s)))
                ((symbol-function 'browse-url) (lambda (u) (setq opened u))))
        (magit-remote-link-copy-at-point)
        (magit-remote-link-browse-at-point))
      (should (equal copied "https://github.com/me/repo/blob/main/a.el#L1"))
      (should (equal opened copied)))))

(ert-deftest mrl-expand-web-url ()
  (string-match "\\`\\(.*\\)/\\(.*\\)\\'" "grp/repo")
  (should (equal (mrl--expand-web-url "%s://%h/\\2/\\1/\\9" '((?s . "https") (?h . "h")) "grp/repo")
                 "https://h/repo/grp/")))

(ert-deftest mrl-encode-path ()
  (should (equal (mrl--encode-path "a b/c#d/é") "a%20b/c%23d/%C3%A9")))

(ert-deftest mrl-format-remaining-providers ()
  (should (equal (mrl-format-url "https://bitbucket.org/me/repo" "main" "a" 3 5)
                 "https://bitbucket.org/me/repo/src/main/a#lines-3:5"))
  (should (equal (mrl-format-url "https://notabug.org/me/repo" "main" "a" 3 5)
                 "https://notabug.org/me/repo/src/main/a#L3-L5"))
  (should (equal (mrl-format-url "https://git.example.com/me/repo" "main" "a" 3 5 'gitea)
                 "https://git.example.com/me/repo/src/branch/main/a#L3-L5")))

;; Local Variables:
;; read-symbol-shorthands: (("mrl-" . "magit-remote-link-"))
;; End:
;;; magit-remote-link-test.el ends here
