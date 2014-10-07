;;; company-cabal.el --- company-mode cabal backend -*- lexical-binding: t -*-

;; Copyright (C) 2014 by Iku Iwasa

;; Author:    Iku Iwasa <iku.iwasa@gmail.com>
;; URL:       https://github.com/iquiw/company-cabal
;; Version:   0.0.0
;; Package-Requires: ((cl-lib "0.5") (company "0.8.0") (emacs "24"))
;; Stability: experimental

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'company)

(require 'company-cabal-fields)

(defgroup company-cabal nil
  "company-mode back-end for haskell-cabal-mode."
  :group 'company)


(defcustom company-cabal-field-value-offset 21
  "Specify column offset filled after field name completion.
Set it to 0 if you want to turn off this behavior."
  :type 'number)

(defconst company-cabal--section-regexp
  "^\\([[:space:]]*\\)\\([[:word:]]+\\)\\([[:space:]]\\|$\\)")

(defconst company-cabal--field-regexp
  "^\\([[:space:]]*\\)\\([[:word:]]+\\):")

(defconst company-cabal--conditional-regexp
  "^\\([[:space:]]*\\)\\(if\\|else\\)[[:space:]]+\\(.*\\)")

(defconst company-cabal--simple-field-regexp
  (concat company-cabal--field-regexp "[[:space:]]*\\([^[:space:]]*\\)"))

(defconst company-cabal--list-field-regexp
  (concat company-cabal--field-regexp
          "\\(?:[[:space:]\n]+[^[:space:]]+,?\\)*?"
          "[[:space:]\n]*\\([^[:space:]]*\\)"))

(defvar company-cabal--prefix-offset nil)

(defvar company-cabal--packages nil)

(defun company-cabal-prefix ()
  "Provide completion prefix at the current point."
  (cond
   ((looking-back "^\\([[:space:]]*\\).*")
    (let ((offset (string-width (match-string-no-properties 1)))
          (prefix (company-grab-symbol)))
      (setq company-cabal--prefix-offset offset)
      (if (= offset 0) prefix
        (save-excursion
          (forward-line -1)
          (while (and (not (bobp)) (looking-at-p "^[[:space:]]*$"))
            (forward-line -1))
          (cond
           ((looking-at company-cabal--section-regexp) prefix)
           ((and (looking-at company-cabal--field-regexp)
                 (or
                  (>= offset (string-width (match-string-no-properties 1)))
                  (member (match-string-no-properties 2)
                          '("build-type" "hs-source-dirs" "type"
                            "build-depends"))))
            prefix))))))))

(defun company-cabal-candidates (prefix)
  "Provide completion candidates for the given PREFIX."
  (pcase (company-cabal--find-context)
    (`(section . ,value)
     (let ((fields
            (cdr (assoc-string value company-cabal--section-field-alist))))
       (all-completions (downcase prefix)
                        (or fields
                            (append company-cabal--sections
                                    company-cabal--pkgdescr-fields)))))
    (`(field . ,value)
     (pcase value
       (`"build-type"
        (all-completions prefix company-cabal--build-type-values))
       (`"hs-source-dirs"
        (all-completions prefix (company-cabal--get-directories)))
       (`"type"
        (pcase (company-cabal--find-current-section)
          (`"benchmark"
           (all-completions prefix company-cabal--benchmark-type-values))
          (`"test-suite"
           (all-completions prefix company-cabal--testsuite-type-values))
          (`"source-repository"
           (all-completions prefix company-cabal--sourcerepo-type-values))))
       (`"build-depends"
        (all-completions prefix (company-cabal--list-packages)))))
    (`(top)
      (all-completions (downcase prefix)
                       (append company-cabal--sections
                               company-cabal--pkgdescr-fields)))))

(defun company-cabal-annotation (candidate)
  "Return type property of CANDIDATE as annotation."
  (let ((type (get-text-property 0 :type candidate)))
    (and type (symbol-name type))))

(defun company-cabal-post-completion (candidate)
  "Capitalize candidate if it starts with uppercase character.
Add colon and space after field inserted."
  (cl-case (get-text-property 0 :type candidate)
    (field
     (let ((end (point)) start)
       (when (save-excursion
               (backward-char (length candidate))
               (setq start (point))
               (let ((case-fold-search nil))
                 (looking-at-p "[[:upper:]]")))
         (delete-region start end)
         (insert (mapconcat 'capitalize (split-string candidate "-") "-"))))
     (insert ": ")
     (let ((col (+ company-cabal-field-value-offset
                   company-cabal--prefix-offset)))
       (if (> col (current-column))
           (move-to-column col t))))))

(defun company-cabal--find-current-section ()
  "Find the current section name."
  (catch 'result
    (save-excursion
      (while (re-search-backward company-cabal--section-regexp nil t)
        (let ((section (match-string-no-properties 2)))
          (when (member section company-cabal--sections)
            (throw 'result (downcase section))))))))

(defun company-cabal--find-parent (offset)
  "Find the parent field or section.
This returns the first field or section with less than given OFFSET."
  (catch 'result
    (let ((ret (forward-line 0)))
      (while (>= ret 0)
        (when (and
               (looking-at "^\\([[:space:]]*\\)\\([[:word:]]+\\)\\(:\\)?")
               (< (string-width (match-string-no-properties 1)) offset))
          (throw 'result
                 (cons (if (match-string 3) 'field 'section)
                       (downcase (match-string-no-properties 2)))))
        (setq ret (forward-line -1))))))

(defun company-cabal--find-context ()
  "Find the completion context at the current point."
  (save-excursion
    (cond
     ((looking-back "^\\([[:space:]]*\\)[^[:space:]]*")
      (let ((offset (string-width (match-string-no-properties 1))))
        (if (= offset 0)
            '(top)
          (company-cabal--find-parent offset))))
     ((looking-back company-cabal--simple-field-regexp)
      (cons 'field (downcase (match-string-no-properties 2))))
     ((progn (beginning-of-line)
             (looking-at "^\\([[:space:]]*\\)"))
      (company-cabal--find-parent
       (string-width (match-string-no-properties 1)))))))

(defun company-cabal--get-directories ()
  "Get top-level directories."
  (let* ((file (buffer-file-name))
         (dir (or (and file (file-name-directory file)) "."))
         result)
    (dolist (f (directory-files dir) result)
      (when (and (file-directory-p f)
                 (not (eq (string-to-char f) ?.)))
        (setq result (cons f result))))))

(defun company-cabal--list-packages ()
  "List installed packages via ghc-pkg."
  (or company-cabal--packages
      (setq company-cabal--packages
            (cl-delete-duplicates
             (split-string
              (shell-command-to-string
               "ghc-pkg list --simple-output --names-only"))
             :test 'string=))))

;;;###autoload
(defun company-cabal (command &optional arg &rest ignored)
  "`company-mode' completion back-end for `haskell-cabal-mode'.
Provide completion info according to COMMAND and ARG.  IGNORED, not used."
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-cabal))
    (prefix (and (derived-mode-p 'haskell-cabal-mode) (company-cabal-prefix)))
    (candidates (company-cabal-candidates arg))
    (ignore-case 'keep-prefix)
    (annotation (company-cabal-annotation arg))
    (post-completion (company-cabal-post-completion arg))))

(provide 'company-cabal)
;;; company-cabal.el ends here
