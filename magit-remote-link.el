;;; magit-remote-link.el --- Actions with remote git hub links -*- lexical-binding: t; -*-

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

;;  Actions with remote git hub links.

;;; Code:

(require 'cl-lib)
(require 'project)

(require 'magit)


;; Customizations:
(defgroup magit-remote-link nil
  "Magit remote link actions."
  :prefix "magit-remote-link-"
  :group 'magit)

;; TODO: display=source for lightweight markups
;; TODO: use this mapping
(defcustom magit-remote-link-git-hosting-providers
  '((github "%s://%s/%s/%s/blob/%s/%s#L%s" "-L%s")
    (gitlab "%s://gitlab.com/%s/%s/-/blob/%s/%s#L%s" "-%s")
    (bitbucket "%s://bitbucket.org/%s/%s/src/%s/%s#lines-%s" ":%s")
    (gitea "%s://%s/%s/%/src/branch/%s/%s#L%s" "-L%s")
    (sourcehut "%s://git.sr.ht/~%s/%s/tree/%s/item/%s#L%s" "-:%s")
    (notabug "%s://notabug.org/%s/%s/src/%s/%s#L%s" "-L%s")
    (codeberg "%s://codeberg.org/%s/%s/src/branch/%s/%s#L%s" "-L%s")
    (gitweb "%s://%s/%s/%s/tree/%s#n%s" ""))
  "A list of git hosting providers and their URLs.
Each item should be a list of three elements:
  - the name of the provider (a symbol)
  - a format string for the URL to link to a single line in a file
  - a format string for the URL to link to a code region in a file,
    with `%s` placeholders for the:
  - scheme,
  - user,
  - repository,
  - branch or commit hash,
  - file path,
  - line or region number."
  :type '(list (list symbol string string))
  :group 'magit-remote-link)


(defconst mrl--url-regex
  (rx
   bol
   (group (or "git+ssh" "git" "http" "https")) (or ?@ "://")  ; scheme
   (group (+ any)) (or ?: ?/)  ; hub hostname
   (group (+ any)) ?/  ; user name
   (group (+? any)) (0+ ".git")   ; project name
   eol)
  "Regex for parsing remote URL.")


(defclass mrl-data ()
  ((scheme :initarg :scheme)
   (base-url :initarg :base-url)
   (user :initarg :user)
   (project :initarg :project)
   (branch :initarg :branch)
   (filename :initarg :filename)
   (lineno :initarg :lineno)
   (endno :initarg :endno))
  :documentation "Structure for creation a full remote URL to a line or a region in a file.")

(cl-defmethod mrl-extend-with-file-context ((data mrl-data))
  "Extend DATA with information about opened file at point (actually buffer)."

  ;; For read-only files opened in a some revision, for example via magit-blame or other diff
  ;; buffer-local variable `magit-buffer-file-name' is not nil and we should take it, because
  ;; more generic `buffer-file-name' will be constructed as temporary string like
  ;; "<filename>.<extension>.~<commit hash>~"
  (setf (slot-value data :filename)
        (or magit-buffer-file-name (file-relative-name buffer-file-name
                                                       (project-root (project-current)))))

  (if (region-active-p)
        (progn (setf (slot-value data :lineno) (line-number-at-pos (region-beginning)))
               (setf (slot-value data :endno) (line-number-at-pos (region-end))))
      (setf (slot-value data :lineno) (line-number-at-pos))
      (setf (slot-value data :endno) nil))

  (setf (slot-value data :branch) (magit-get-current-branch)))

(cl-defmethod mrl-format-url ((data mrl-data))
  "Build full URL for git repository provider from DATA object."
  (with-slots (scheme base-url user project branch filename lineno endno) data
    (let ((url (format "%s://%s/%s/%s/blob/%s/%s#L%s"
                       (mrl-get-http-url-scheme scheme)
                       base-url
                       user
                       project
                       branch
                       filename
                       lineno)))
      (when endno (setf url (format "%s-L%s" url endno)))
      url)))


(defun mrl-get-http-url-scheme (scheme)
  "Return HTTP or HTTPS based on DATA's original SCHEME, HTTPS is preferred."
  (cond ((or (string= scheme "http") (string= scheme "https"))
         scheme)
        (t "https")))

(defun mrl--get-current-remote-url ()
  "Return current remote URL."
  ;; TODO: find out how to get current remote properly (see (magit-get-current-remote))
  (magit-get "remote" (substring-no-properties (magit-read-remote "Remote repository" "origin")) "url"))

(defun mrl--parse-remote-url% (url)
  "Parse remote URL and return data as a list."
  (save-match-data
    (when (string-match mrl--url-regex url)
      (list (match-string 1 url)
            (match-string 2 url)
            (match-string 3 url)
            (match-string 4 url)))))

(defun mrl--parse-remote-url (url)
  "Parse remote URL and fill our data object with extracted data."
  (save-match-data
    (when (string-match mrl--url-regex url)
      (cl-destructuring-bind (scheme base-url user project) (magit-remote-link--parse-remote-url% url)
        (make-instance 'mrl-data
                       :scheme scheme
                       :base-url base-url
                       :user user
                       :project project)))))

(defun mrl--get-current-remote-url-data ()
  "Get remote URL data for the current remote."
  (mrl--parse-remote-url (mrl--get-current-remote-url)))

(defun mrl--get-current-remote-data-at-point ()
  "Get filled context data about thing at point ready to construct remote URL."
  (let ((data (mrl--get-current-remote-url-data)))
    (mrl-extend-with-file-context data)
    data))

;;;###autoload
(defun magit-remote-link-copy-at-point ()
  "Copy remote URL with a line at the point or an active region to the clipboard."
  (interactive)
  (let ((remote-url (mrl-format-url (mrl--get-current-remote-data-at-point))))
    (kill-new remote-url)
    (message "Copied: %s" remote-url)))

;;;###autoload
(defun magit-remote-link-browse-at-point ()
  "Open remote URL in browser to a line at the point or an active region."
  (interactive)
  (let ((remote-url (mrl-format-url (mrl--get-current-remote-data-at-point))))
    (browse-url remote-url)
    (message "Opening: %s" remote-url)))

(provide 'magit-remote-link)

;; Local Variables:
;; read-symbol-shorthands: (("mrl-" . "magit-remote-link-"))
;; End:
;;; magit-remote-link.el ends here
