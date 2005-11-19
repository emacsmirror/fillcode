;; fillcode.el --- Fillcode minor mode
;;
;; Fillcode
;; http://snarfed.org/space/fillcode
;; Copyright 2005 Ryan Barrett <fillcode@ryanb.org>
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; A copy of the GNU General Public License can be obtained at
;; http://www.gnu.org/licenses/gpl.html or from the Free Software Foundation,
;; Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;; LCD Archive Entry:
;; fillcode|Ryan Barrett|fillcode@ryanb.org|
;; Minor mode to fill function calls and other parts of source code|
;; 7-September-2005|0.1|~/packages/fillcode.el|

;; This minor mode enhance the fill functions when in source code major modes,
;; such as c-mode, java-mode, and python-mode. Specifically, it provides a new
;; fill function that intelligently fills some parts of source code, like
;; function calls and definitions, if the language mode's fill function
;; doesn't already.
;;
;; M-x fillcode-mode toggles fillcode-mode on and off in the current buffer.
;;
;; TODO:
;; - if first arg doesn't pass fill-column, but next one does, newline first
;;   (maybe option for preferring first arg on first line or on next line?)
;; - add beginning-of-statement fns for more languages
;; - fill things besides function calls, eg arithmetic expressions, string
;;   constants (language specific, ick), java throws clauses
;; - make it compatible with filladapt-mode
;; - somehow include the assignment = operator and <, > in
;;   fillcode-fill-point-re. (how to handle <, > with e.g. templates?!?)

(require 'cl)  ; for the case macro

(defvar fillcode-version "0.1")

(define-minor-mode fillcode-mode
  "Toggle fillcode mode.
With no argument, this command toggles the mode. Non-null prefix argument
turns on the mode. Null prefix argument turns off the mode.

Fillcode mode can intelligently fill some parts of source code, like function
calls and definitions, in many languages.

For more information, see http://snarfed.org/space/fillcode
"
 ;; initial value
 nil
 ;; mode line indicator
 " Fillcode"
 ;; keymap
 nil
 ;; these forms run when fillcode-mode is enabled or disabled. the
 ;; fillcode-mode var is set before these forms run.
 (make-local-variable              ;; The primary fill function. Fillcode only
  'fillcode-wrapped-fill-function) ;; runs if this returns nil.
 (make-local-variable 'fill-paragraph-function)
 (if fillcode-mode
     ; this runs when fillcode is enabled...
     (progn 
       (if (not (eq fill-paragraph-function 'fillcode-fill-paragraph))
           (setq fillcode-wrapped-fill-function fill-paragraph-function)
         (setq fillcode-wrapped-fill-function nil))
       (setq fill-paragraph-function 'fillcode-fill-paragraph)
       (ad-activate 'c-fill-paragraph))
   ; ...and this runs when it's disabled.
   (progn
     (if (eq fill-paragraph-function 'fillcode-fill-paragraph)
         (setq fill-paragraph-function fillcode-wrapped-fill-function))
     (ad-deactivate 'c-fill-paragraph))
   )
 )

(defadvice c-fill-paragraph (around fillcode-if-in-code)
  "Fill code even in `cc-mode'.

`cc-mode' replaces `fill-paragraph' with its own function, `c-fill-paragraph',
which only calls fill-paragraph if it's inside a comment or string literal, and
narrows to that comment or string literal. Fillcode operates on code itself, so
it needs a chance to run (without narrowing!), which this advice provides."
  (let ((fill-paragraph-function nil))
    ad-do-it)
  (fillcode-fill-paragraph nil)
  )


(defgroup fillcode nil
  "Fill code"
  :group 'fill)

(defcustom fillcode-nested-calls-are-sticky nil
  "If non-nil, fillcode will not separate a nested call's first argument.
\(This does *not* apply to the outermost function call.) For example, if this
variable is non-nil, this:

foo(bar, baz(baj))

will fill to:

foo(bar,
    baz(baj))

If this variable is nil, it will fill to:

foo(bar, baz(
    baj))"
  :type 'boolean
  :group 'fillcode)

(defcustom fillcode-fill-point-re
  (concat ",\\|"
          "\\([+-/*][^=+-]\\)\\|"
          "==\\|!=\\|||\\|&&\\|<=\\|>=")
  "A regular expression used to find the next fill point.
A fill point is a point in an expression where a newline can reasonably be
inserted. You may modify this to allow fillcode to handle new languages.

The single = (assignment) operator and < and > operators are notably absent."
  :type 'string
  :group 'fillcode)


(defun fillcode-fill-paragraph (arg &optional arg2 arg3 arg4)
  "Fill code at point if fillcode-wrapped-fill-function is nil.

If fillcode-wrapped-fill-function is nil, fills code. If it's non-nil, runs it
first, and only fills code if it returns nil.

Intended to be set as fill-paragraph-function."
  (save-excursion
    ; first, see if the original fill function does anything
    (let ((ret (if fillcode-wrapped-fill-function
                   (apply fillcode-wrapped-fill-function arg)
                 nil)))
      ; if it does, don't do anything
      (if ret
          ret
        ; if it doesn't, fill code
        (if (fillcode-beginning-of-statement)
            (fillcode)
          nil)))
    ))



(defun fillcode ()
  "Fill code at point.
The actual function-call-filling algorithm. Fills function calls and prototypes
if it thinks the point is on a statement that has one."
  (interactive)
  (collapse-whitespace-forward)

  ; the main loop. advances through the statement, normalizing whitespace and
  ; deleting newlines along the way. the main loop should run once once and
  ; only once for each printable character. when we hit the fill-column, fill
  ; intelligently.
  (catch 'closeparen
    (while (char-after)
      (let ((c (char-to-string (char-after))))
;;         (edebug)
        ; fill if we need to
        (if (fillcode-should-fill)
            (progn
              (fillcode-find-fill-point-backward)
              (newline-and-indent)))
        ; open parenthesis is our recursive step; recurse!
        (if (equal c "(")
            (fillcode))
        ; close parenthesis is our base case; return!
        (if (equal c ")")
            (throw 'closeparen t))
        ; next!
        (collapse-whitespace-forward)
        )))

  ; if this is a nested function call, and we filled, newline after next comma
;;   (if (and arg
;;            (save-excursion
;;              (skip-chars-backward "^(" (line-beginning-position))
;;              (eq (point) (line-beginning-position))))
;;       (progn
;;         (collapse-whitespace-forward)  ; move past close paren
;;         (if (equal "," (char-to-string (char-after)))
;;             (progn
;;               (delete-horizontal-space)
;;               (forward-char)  ; move past comma
;;               (collapse-whitespace-forward)
;;               (newline-and-indent)))))

  ; return t to indicate that we filled something
  t
)


(defun fillcode-beginning-of-statement ()
  "Find the beginning of the statement that point is currently in.
Calls the major mode's beginning-of-statement function, if it has one.
Otherwise, for safety, just goes to the beginning of the line.

`c-beginning-of-statement' might be a good fallback for unknown languages, but
it occasionally fails badly, e.g. in `perl-mode' in some cases."
  (case major-mode
    ((c-mode c++-mode java-mode objc-mode)
     (c-beginning-of-statement))
    ((python-mode)
     (py-goto-statement-at-or-above))
    ((perl-mode)
     (c-beginning-of-statement))
    (otherwise
     (beginning-of-line)))  ; default

  (search-forward "(" (line-end-position) t)
  )


(defun collapse-whitespace-forward ()
  "Delete newlines and normalize whitespace.
Specifically, no spaces before commas or open parens or after close parens,
one space after commas, one space before and after arithmetic operators. Then
advance point to next non-whitespace char."
  (interactive)
  (let* ((whitespace-chars " \t\n")
         (need-collapse-re (concat "[()" whitespace-chars "]\\|"
                                   fillcode-fill-point-re)))
  ; if we're on whitespace or stop chars, delete and normalize it...
    (if (looking-at need-collapse-re)
      (progn
        (delete-horizontal-space)

        ; if we're at the end of the line, pull up the next line
        (if (eolp)
            (delete-indentation t)
          ; otherwise insert a space, if necessary, and advance
          (progn
            (if (not (looking-at need-collapse-re))
                (fixup-whitespace))
            (if (looking-at need-collapse-re)
                (forward-char)))))

    ; else if we're after a comma, normalize to one space
      (if (equal "," (char-to-string (char-before)))
          (fixup-whitespace)

      ; ...otherwise, base case: advance one char
        (forward-char)))
    ))

(defun fillcode-should-fill ()
  "Return t if we should fill at the last fill point, nil otherwise.

We should fill if:

- there's a fill point on this line, AND EITHER

- the current char is at or beyond `fill-column' OR

- the current char is the close paren of a nested call, and the next char is a
  comma. (have to look ahead like this so that we don't end up past the close
  paren, and miss the close paren base case, which would screw up the stack.)"
  (and
   ; fill point on this line?
   (save-excursion
     (catch 'no-fill-point
       (fillcode-find-fill-point-backward)
       t))
   ; past fill-column?
   (or (>= (current-column) fill-column)
       ; this is a close paren, and next is a fill point past fill-column?
       (save-excursion
         (and arg
            (equal c ")")
            (skip-chars-forward ") \t\n")
            (looking-at fillcode-fill-point-re)
            (>= (current-column) fill-column))))
   ))


(defun fillcode-find-fill-point-backward ()
  "Move point to the closest preceding fill point on the current line.
Fill points are commas, open parens (if fillcode-nested-calls-are-sticky is
off) and eventually arithmetic operators, ||s, &&s, etc.

If there's no fill point on the current line, throws no-fill-point."
;;   (let* ((fill-point-chars
;;           (if fillcode-nested-calls-are-sticky "),+-/*" "(),+-/*"))
;;          (fill-point-re
;;           (concat "[" fill-point-chars "][^" fill-point-chars "]")))
  (let ((fill-point-re
          (if fillcode-nested-calls-are-sticky
              fillcode-fill-point-re
              (concat "(\\|" fillcode-fill-point-re))))

    (forward-char)
    (condition-case nil
        (re-search-backward fill-point-re (line-beginning-position))
      (search-failed (throw 'no-fill-point nil)))

    (forward-char)
    ))


(provide 'fillcode)

;;; fillcode.el ends here
