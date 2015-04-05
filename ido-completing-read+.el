;; -*- lexical-binding: t -*-

;;; ido-completing-read+.el --- A completing-read-function using ido
;; 
;; Filename: ido-completing-read+.el
;; Author: Ryan Thompson
;; Created: Sat Apr  4 13:41:20 2015 (-0700)
;; Version: 0.1
;; Package-Requires: ((emacs "24.1"))
;; URL: https://github.com/DarwinAwardWinner/ido-ubiquitous
;; Keywords: ido, completion, convenience
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Commentary: 
;; 
;; This package implments the `ido-completing-read+' function, which
;; is a wrapper for `ido-completing-read'. Importantly, it detects
;; edge cases that ordinary ido cannot handle and either adjusts them
;; so ido *can* handle them, or else simply falls back to Emacs'
;; standard completion instead.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;; 
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Code:

(require 'cl-macs)

(defvar ido-cr+-enable-next-call nil
  "If non-nil, then the next call to `ido-completing-read' is by `ido-completing-read+'.")
(defvar ido-cr+-enable-this-call nil
  "If non-nil, then the current call to `ido-completing-read' is by `ido-completing-read+'")

(defcustom ido-cr+-fallback-function
  ;; Initialize to the current value of `completing-read-function',
  ;; unless that is already set to the ido completer, in which case
  ;; use `completing-read-default'.
  (if (memq completing-read-function
            '(ido-completing-read+ ido-completing-read))
      'completing-read-default
    completing-read-function)
  "Alternate completing-read function to use when ido is not wanted.

This will be used for functions that are incompatibile with ido
or if ido cannot handle the completion arguments. It will also be
used when the user requests non-ido completion manually via C-f
or C-b."
  :type '(choice (const :tag "Standard emacs completion"
                        completing-read-default)
                 (function :tag "Other function"))
  :group 'ido-completing-read+)

(defcustom ido-cr+-max-items 30000
  "Max collection size to use ido-cr+ on.

If `ido-completing-read+' is called on a collection larger than
this, the fallback completion method will be used instead. To
disable fallback based on collection size, set this to nil."
  :type '(choice (const :tag "No limit" nil)
                 (integer
                  :tag "Limit" :value 5000
                  :validate
                  (lambda (widget)
                    (let ((v (widget-value widget)))
                      (if (and (integerp v)
                               (> v 0))
                          nil
                        (widget-put widget :error "This field should contain a positive integer")
                        widget)))))
  :group 'ido-completing-read+)

;; Signal used to trigger fallback
(define-error 'ido-cr+-fallback "ido-cr+-fallback")

(defun ido-completing-read+ (prompt collection &optional predicate
                                    require-match initial-input
                                    hist def inherit-input-method)
  "ido-based method for reading from the minibuffer with completion.

See `completing-read' for the meaning of the arguments.

This function is a wrapper for `ido-completing-read' designed to
be used as the value of `completing-read-function'. Importantly,
it detects edge cases that ido cannot handle and uses normal
completion for them."
  (let (;; Save the original arguments in case we need to do the
        ;; fallback
        (orig-args
         (list prompt collection predicate require-match
               initial-input hist def inherit-input-method)))
    (condition-case nil
        (progn
          (when (or
                 ;; Can't handle this arg
                 inherit-input-method
                 ;; Can't handle this being set
                 (bound-and-true-p completion-extra-properties)
                 ;; Can't handle functional collection
                 (functionp collection))
            (signal 'ido-cr+-fallback nil))
          ;; Expand all possible completions
          (setq collection (all-completions "" collection predicate))
          ;; Check for excessively large collection
          (when (and ido-cr+-max-items
                     (> (length collection) ido-cr+-max-items))
            (signal 'ido-cr+-fallback nil))
          ;; ido doesn't natively handle DEF being a list. If DEF is
          ;; a list, prepend it to CHOICES and set DEF to just the
          ;; car of the default list.
          (when (and def (listp def))
            (setq choices
                  (append def
                          (nreverse (cl-set-difference choices def)))
                  def (car def)))
          ;; Work around a bug in ido when both INITIAL-INPUT and
          ;; DEF are provided.
          (let ((initial
                 (or (if (consp initial-input)
                         (car initial-input)
                       initial-input)
                     "")))
            (when (and def initial
                       (stringp initial)
                       (not (string= initial "")))
              ;; Both default and initial input were provided. So
              ;; keep the initial input and preprocess the choices
              ;; list to put the default at the head, then proceed
              ;; with default = nil.
              (setq choices (cons def (remove def choices))
                    def nil)))
          ;; Ready to do actual ido completion
          (prog1
              (let ((ido-cr+-enable-next-call t))
                (ido-completing-read
                 prompt collection
                 predicate require-match initial-input hist def
                 inherit-input-method))
            ;; This detects when the user triggered fallback mode
            ;; manually.
            (when (eq ido-exit 'fallback)
              (signal 'ido-cr+-fallback nil))))
      ;; Handler for ido-cr+-fallback signal
      (ido-cr+-fallback
       (apply ido-cr+-fallback-function orig-args)))))

(defadvice ido-completing-read (around ido-cr+ activate)
  "Ensure that `ido-cr+-enable-this-call' is set properly.

This variable should be non-nil while executing
`ido-completing-read' if it was called from
`ido-completing-read+'."
  (let ((ido-cr+-enable-this-call ido-cr+-enable-next-call)
        (ido-cr+-enable-next-call nil))
    ad-do-it))

;; Fallback on magic C-f and C-b
(defadvice ido-magic-forward-char (before ido-cr+-fallback activate)
  "Allow falling back in ido-completing-read+."
  (message "ido-cr+-enable-this-call is %S" ido-cr+-enable-this-call)
  (when ido-cr+-enable-this-call
    ;; `ido-context-switch-command' is already let-bound at this
    ;; point.
    (setq ido-context-switch-command #'ido-fallback-command)))

(defadvice ido-magic-backward-char (before ido-cr+-fallback activate)
  "Allow falling back in ido-completing-read+."
  (when ido-cr+-enable-this-call
    ;; `ido-context-switch-command' is already let-bound at this
    ;; point.
    (setq ido-context-switch-command #'ido-fallback-command)))

(provide 'ido-completing-read+)

;;; ido-completing-read+.el ends here