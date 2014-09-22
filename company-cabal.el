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
  (concat company-cabal--field-regexp "[[:space:]]*\\([[:word:]]*\\)"))

(defvar company-cabal--prefix-offset nil)

(defun company-cabal-prefix ()
  "Provide completion prefix at the current point."
  (cond
   ((company-grab "^\\([[:space:]]*\\)\\([[:word:]]*\\)")
    (let ((offset (string-width (match-string-no-properties 1)))
          (prefix (match-string-no-properties 2)))
      (setq company-cabal--prefix-offset offset)
      (if (= offset 0) prefix
        (save-excursion
          (forward-line -1)
          (while (and (not (bobp)) (looking-at-p "^[[:space:]]*$"))
            (forward-line -1))
          (cond
           ((looking-at company-cabal--section-regexp) prefix)
           ((and (looking-at company-cabal--field-regexp)
                 (<= offset (string-width (match-string-no-properties 1))))
            prefix))))))
   ((and (company-grab company-cabal--simple-field-regexp)
         (member (match-string-no-properties 2)
                 '("build-type" "type")))
    (match-string-no-properties 3))))

(defun company-cabal-candidates (prefix)
  "Provide completion candidates for the given PREFIX."
  (cond
   ((company-grab company-cabal--simple-field-regexp)
    (let ((field (match-string-no-properties 2)))
      (pcase field
        (`"build-type"
         (all-completions prefix company-cabal--build-type-values))
        (`"type"
         (pcase (company-cabal--find-current-section)
           (`"benchmark"
            (all-completions prefix company-cabal--benchmark-type-values))
           (`"test-suite"
            (all-completions prefix company-cabal--testsuite-type-values))
           (`"source-repository"
            (all-completions prefix company-cabal--sourcerepo-type-values)))))))
   (t
    (let ((fields
           (save-excursion
             (beginning-of-line)
             (catch 'result
               (while (re-search-backward company-cabal--section-regexp nil t)
                 (when (> company-cabal--prefix-offset
                          (string-width (match-string-no-properties 1)))
                   (throw 'result
                          (cdr (assoc-string
                                (downcase (match-string-no-properties 2))
                                company-cabal--section-field-alist)))))))))
      (all-completions (downcase prefix)
                       (or fields
                           (append company-cabal--sections
                                   company-cabal--pkgdescr-fields)))))))

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
            (throw 'result section)))))))

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
    (post-completion (company-cabal-post-completion arg))))

(provide 'company-cabal)
;;; company-cabal.el ends here
