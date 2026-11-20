;;; magit-remote-link.el --- Links to files on git hosting services -*- lexical-binding: t; -*-

;; Copyright (C) 2023 Pavel Kulyov <kulyov.pavel@gmail.com>

;; Author: Pavel Kulyov <kulyov.pavel@gmail.com>
;; Maintainer: Pavel Kulyov <kulyov.pavel@gmail.com>
;; Version: 1.0.0
;; Keywords: tools
;; URL: https://github.com/pkulev/magit-remote-link.el
;; Package-Requires: ((emacs "28.1") (magit "3.0.0"))

;; This file is NOT part of GNU/Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Copy or browse the web URL of the line or region at point on the remote
;; hosting service (GitHub, GitLab, cgit, ...).  Hosts are recognized by
;; `magit-remote-link-hosts', and a single remote can be configured with the git
;; config keys `remote.NAME.magit-remote-link-provider' and
;; `remote.NAME.magit-remote-link-url'.

;;; Code:

(require 'cl-lib)
(require 'format-spec)
(require 'rx)
(require 'url-util)

(require 'magit)


;; Customizations:
(defgroup magit-remote-link nil
  "Magit remote link actions."
  :prefix "magit-remote-link-"
  :group 'magit)

(defcustom magit-remote-link-git-hosting-providers
  '((github    "%w/blob/%b/%f#L%l"            "%w/blob/%b/%f#L%l-L%e")
    (gitlab    "%w/-/blob/%b/%f#L%l"          "%w/-/blob/%b/%f#L%l-%e")
    (bitbucket "%w/src/%b/%f#lines-%l"        "%w/src/%b/%f#lines-%l:%e")
    (gitea     "%w/src/branch/%b/%f#L%l"      "%w/src/branch/%b/%f#L%l-L%e")
    (codeberg  "%w/src/branch/%b/%f#L%l"      "%w/src/branch/%b/%f#L%l-L%e")
    (sourcehut "%w/tree/%b/item/%f#L%l"       "%w/tree/%b/item/%f#L%l-%e")
    (notabug   "%w/src/%b/%f#L%l"             "%w/src/%b/%f#L%l-L%e")
    ;; cgit has no range anchors, so a region links to its first line.
    (cgit      "%w/tree/%f?h=%b#n%l"          "%w/tree/%f?h=%b#n%l"))
  "A list of git hosting providers and their file URL layouts.
Each item is a list of three elements:
  - the name of the provider (a symbol)
  - a template for the URL of a single line in a file
  - a template for the URL of a region of a file
Templates are expanded with `format-spec' using these specs:
  - %w, the web base URL of the repository
  - %b, the branch name or commit hash
  - %f, the file path relative to the repository root
  - %l, the line number (the first line of a region)
  - %e, the last line of a region"
  :type '(repeat (list symbol string string))
  :group 'magit-remote-link)

(defcustom magit-remote-link-hosts
  '(("\\`github\\.com/"    github)
    ("\\`gitlab\\.com/"    gitlab)
    ("\\`bitbucket\\.org/" bitbucket)
    ("\\`codeberg\\.org/"  codeberg)
    ("\\`git\\.sr\\.ht/"   sourcehut)
    ("\\`notabug\\.org/"   notabug)
    ("\\`git\\.savannah\\.\\(?:non\\)?gnu\\.org/\\(?:srv/\\)?git/\\(.*\\)\\'"
     cgit "https://cgit.git.savannah.nongnu.org/cgit/\\1.git"))
  "Rules mapping a remote to its hosting provider and web URL.
Each item is a list (REGEXP PROVIDER [WEB-URL]).  REGEXP is matched
against the remote's \"HOST/PATH\", where PATH has no leading slash
and no \".git\" suffix.  The first matching rule wins.  PROVIDER is a
key of `magit-remote-link-git-hosting-providers'.

WEB-URL is a template for the repository's web base URL, expanded with
`format-spec' using %s (\"http\" or \"https\"), %h (host) and %p (path);
\\1 to \\9 are replaced by the matching groups of REGEXP.  It defaults to
\"%s://%h/%p\".

A remote matching no rule is treated as a `github'-style host.  A single
remote can be overridden with the git config keys
`remote.NAME.magit-remote-link-provider' and
`remote.NAME.magit-remote-link-url' (the literal web base URL)."
  :type '(repeat (list regexp symbol (choice (const :tag "Default" nil) string)))
  :group 'magit-remote-link)


(defconst mrl--scheme-url-regex
  (rx bol (+ (any alnum ?+ ?-)) "://"
      (? (+ (not (any ?@ ?/))) ?@)        ; user
      (group (+ (not (any ?: ?/))))       ; host
      (? ?: (+ digit))                    ; port
      ?/
      (group (*? anychar)) (? ".git") (? ?/) eol)
  "Regex for remote URLs like ssh://user@host/path.git.")

(defconst mrl--scp-url-regex
  (rx bol
      (? (+ (not (any ?@ ?/))) ?@)        ; user
      (group (+ (not (any ?: ?/))))       ; host
      ?: (? ?/)
      (group (*? anychar)) (? ".git") (? ?/) eol)
  "Regex for scp-style remote URLs like user@host:path.git.")


(defun mrl--parse-remote-url (url)
  "Parse the git remote URL into a plist of :scheme, :host and :path, or nil.
Both URL schemes (https://, ssh://, git+ssh://, ...) and scp-style
`user@host:path' remotes are understood.  The path has no leading
slash and no \".git\" suffix."
  (save-match-data
    (cond ((string-match mrl--scheme-url-regex url)
           (list :scheme (if (string-prefix-p "http://" url) "http" "https")
                 :host (match-string 1 url)
                 :path (match-string 2 url)))
          ((string-match mrl--scp-url-regex url)
           (list :scheme "https"
                 :host (match-string 1 url)
                 :path (match-string 2 url))))))

(defun mrl--expand-web-url (template specs string)
  "Expand TEMPLATE using `format-spec' SPECS and the last match on STRING.
Occurrences of \\N in TEMPLATE are replaced by group N of that match.
`format-spec' can't do this itself because it reads %N as a field width."
  (let ((groups (cl-loop for i from 1 to 9 collect (match-string i string))))
    (replace-regexp-in-string
     (rx ?\\ (group (any "1-9")))
     (lambda (m) (or (nth (1- (string-to-number (match-string 1 m))) groups) ""))
     (format-spec template specs)
     t t)))

(defun mrl--resolve-host (info)
  "Return (PROVIDER . WEB-URL) for the parsed remote INFO.
The result is looked up in `magit-remote-link-hosts', falling back to
a `github'-style layout under the remote's own host."
  (let* ((scheme (plist-get info :scheme))
         (host (plist-get info :host))
         (path (plist-get info :path))
         (key (concat host "/" path))
         (specs (list (cons ?s scheme) (cons ?h host) (cons ?p path))))
    (save-match-data
      (cl-loop for (regexp provider web-url) in magit-remote-link-hosts
               when (string-match regexp key)
               return (cons provider
                            (mrl--expand-web-url (or web-url "%s://%h/%p") specs key))
               finally return (cons 'github (format-spec "%s://%h/%p" specs))))))

(defun mrl--encode-path (path)
  "Percent-encode PATH for use in a URL, keeping its slashes."
  (mapconcat #'url-hexify-string (split-string path "/") "/"))

(defun mrl-format-url (remote-url branch file line end &optional provider web-url)
  "Build the web URL of FILE at LINE (to END if non-nil) in REMOTE-URL.
BRANCH is a branch name or commit hash and FILE is relative to the
repository root.  PROVIDER (a symbol) and WEB-URL override what
`magit-remote-link-hosts' would infer from REMOTE-URL.  Signal a
`user-error' if REMOTE-URL cannot be parsed or PROVIDER is unknown."
  (let* ((info (or (mrl--parse-remote-url remote-url)
                   (user-error "Cannot parse remote URL: %s" remote-url)))
         (resolved (mrl--resolve-host info))
         (provider (or provider (car resolved)))
         (entry (or (assq provider magit-remote-link-git-hosting-providers)
                    (user-error "Unknown git hosting provider: %s" provider)))
         (template (if end (nth 2 entry) (nth 1 entry))))
    (format-spec template
                 `((?w . ,(string-remove-suffix "/" (or web-url (cdr resolved))))
                   (?b . ,(mrl--encode-path branch))
                   (?f . ,(mrl--encode-path file))
                   (?l . ,(number-to-string line))
                   (?e . ,(and end (number-to-string end)))))))

(defun mrl--current-lines ()
  "Return (START . END) line numbers for the active region or the current line.
END is nil unless the region spans several lines.  A region ending at the
start of a line doesn't include that line, which is what a line-wise
selection looks like."
  (if (not (region-active-p))
      (cons (line-number-at-pos nil t) nil)
    (let* ((beg (region-beginning))
           (end (if (and (> (region-end) beg)
                         (save-excursion (goto-char (region-end)) (bolp)))
                    (1- (region-end))
                  (region-end)))
           (start-line (line-number-at-pos beg t))
           (end-line (line-number-at-pos end t)))
      (cons start-line (and (> end-line start-line) end-line)))))

(defun mrl--current-url ()
  "Prompt for a remote and return the web URL for the line or region at point."
  (let* ((remote (substring-no-properties (magit-read-remote "Remote repository" "origin")))
         (config (lambda (key)
                   (magit-get "remote" remote (concat "magit-remote-link-" key))))
         (provider (funcall config "provider"))
         (branch (or (magit-get-current-branch) (magit-rev-parse "HEAD")))
         (lines (mrl--current-lines))
         ;; Unlike `buffer-file-name', which for a blob at some revision is a
         ;; temporary name like "<file>.~<hash>~", this is always relative to
         ;; the repository root.
         (file (or (magit-file-relative-name)
                   (user-error "Buffer is not visiting a file in a Git repository"))))
    (mrl-format-url (or (magit-get "remote" remote "url")
                        (user-error "Remote %s has no URL" remote))
                    branch
                    file
                    (car lines)
                    (cdr lines)
                    (and provider (intern provider))
                    (funcall config "url"))))

;;;###autoload
(defun magit-remote-link-copy-at-point ()
  "Copy remote URL with a line at the point or an active region to the clipboard."
  (interactive)
  (let ((remote-url (mrl--current-url)))
    (kill-new remote-url)
    (message "Copied: %s" remote-url)))

;;;###autoload
(defun magit-remote-link-browse-at-point ()
  "Open remote URL in browser to a line at the point or an active region."
  (interactive)
  (let ((remote-url (mrl--current-url)))
    (browse-url remote-url)
    (message "Opening: %s" remote-url)))

(provide 'magit-remote-link)

;; Local Variables:
;; read-symbol-shorthands: (("mrl-" . "magit-remote-link-"))
;; End:
;;; magit-remote-link.el ends here
