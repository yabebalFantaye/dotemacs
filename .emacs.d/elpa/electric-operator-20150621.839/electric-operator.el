;;; -*- lexical-binding: t; -*-
;;; electric-operator.el --- Automatically add spaces around operators

;; Copyright (C) 2015 Free Software Foundation, Inc.

;; Author: David Shepherd <davidshepherd7@gmail.com>
;; Version: 0.1
;; Package-Version: 20150621.839
;; Package-Requires: ((dash "2.10.0") (names "20150618.0"))
;; Keywords: electric
;; URL: https://github.com/davidshepherd7/electric-operator

;;; Commetary:

;; An emacs minor-mode to automatically add spacing around operators. For
;; example typing `a=10*5+2' results in `a = 10 * 5 + 2'.

;;; Code:

(require 'cc-mode)
(require 'thingatpt)

(require 'dash)
(require 'names)

;; namespacing using names.el:
;;;###autoload
(define-namespace electric-operator-

;; Tell names that it's ok to expand things inside these threading macros.
:functionlike-macros (-> ->>)



;;; Customisable variables

(defcustom double-space-docs nil
  "Enable double spacing of . in document lines - e,g, type '.' => get '.  '."
  :type 'boolean
  :group 'electricity)

(defcustom enable-in-docs nil
  "Enable electric-operator in strings and comments."
  :type 'boolean
  :group 'electricity)



;;; Other variables

(defvar mode-rules-table
  (make-hash-table)
  "A hash table of replacement rule lists for specific major modes")



;;; Rule list helper functions

(defun -add-rule (initial new-rule)
  "Replace or append a new rule

Returns a modified copy of the rule list."
  (let* ((op (car new-rule))
         (existing-rule (assoc op initial)))
    (if existing-rule
        (-replace-first existing-rule new-rule initial)
      (-snoc initial new-rule))))

(defun -add-rule-list (initial new-rules)
  "Replace or append a list of rules

Returns a modified copy of the rule list."
  (-reduce #'-add-rule (-concat (list initial) new-rules)))

(defun add-rules (initial &rest new-rules)
  "Replace or append multiple rules

Returns a modified copy of the rule list."
  (-add-rule-list initial new-rules))

(defun add-rules-for-mode (major-mode-symbol &rest new-rules)
  "Replace or add spacing rules for major mode

Destructively modifies mode-rules-table to use the new rules for
the given major mode."
  (puthash major-mode-symbol
           (-add-rule-list (gethash major-mode-symbol mode-rules-table)
                           new-rules)
           mode-rules-table))



;;; Default rule lists

(defvar prog-mode-rules
  (list (cons "=" " = ")
        (cons "<" " < ")
        (cons ">" " > ")
        (cons "%" " % ")
        (cons "+" " + ")
        (cons "-" #'prog-mode--)
        (cons "*" " * ")
        (cons "/" #'prog-mode-/)
        (cons "&" " & ")
        (cons "|" " | ")
        (cons "?" "? ")
        (cons "," ", ")
        (cons "^" " ^ ")

        (cons "==" " == ")
        (cons "!=" " != ")
        (cons "<=" " <= ")
        (cons ">=" " >= ")

        (cons "*=" " *= ")
        (cons "+=" " += ")
        (cons "/=" " /= ")
        (cons "-=" " -= ")
        (cons "&=" " &= ")
        (cons "|=" " |= ")

        (cons "&&" " && ")
        (cons "||" " || ")
        )
  "Default spacing rules for programming modes")

(defvar prose-rules
  (add-rules '()
             (cons "." #'docs-.)
             (cons "," ", ")
             )
  "Rules to use in comments, strings and text modes.")



;;; Core functions

(defun get-rules-list ()
  "Pick which rule list is appropriate for spacing at point"
  (cond
   ;; In comment or string?
   ((in-docs?) (if enable-in-docs prose-rules (list)))

   ;; Try to find an entry for this mode in the table
   ((gethash major-mode mode-rules-table))

   ;; Default modes
   ((derived-mode-p 'prog-mode) prog-mode-rules)
   (t prose-rules)))

(defun rule-regex-with-whitespace (op)
  "Construct regex matching operator and any whitespace before/inside/after

For example for the operator '+=' we allow '+=', ' +=', '+ ='. etc.
"
  (mapconcat 'identity (-map #'regexp-quote (split-string op "")) "\s*"))

(defun longest-matching-rule (rule-list)
  "Return the rule with the most characters that applies to text before point"
  (->> rule-list
       (-filter (lambda (rule) (looking-back (rule-regex-with-whitespace (car rule)))))
       (-sort (lambda (p1 p2) (> (length (car p1)) (length (car p2)))))
       (car)))

(defun post-self-insert-function ()
  "Check for a matching rule and apply it"
  (-let* ((rule (longest-matching-rule (get-rules-list)))
          ((operator . action) rule))
    (when (and rule action)

      ;; Delete the characters matching this rule before point
      (looking-back (rule-regex-with-whitespace operator) nil t)
      (let ((match (match-data)))
        (delete-region (nth 0 match) (nth 1 match)))

      ;; Insert correctly spaced operator
      (if (stringp action)
          (insert action)
        (insert (funcall action))))))

:autoload
(define-minor-mode mode
  "Toggle automatic insertion of spaces around operators (Electric Spacing mode).

With a prefix argument ARG, enable Electric Spacing mode if ARG is
positive, and disable it otherwise.  If called from Lisp, enable
the mode if ARG is omitted or nil.

This is a local minor mode.  When enabled, typing an operator automatically
inserts surrounding spaces, e.g., `=' becomes ` = ',`+=' becomes ` += '."
  :global nil
  :group 'electricity
  :lighter " _+_"

  ;; body
  (if mode
      (add-hook 'post-self-insert-hook
                #'post-self-insert-function nil t)
    (remove-hook 'post-self-insert-hook
                 #'post-self-insert-function t)))



;;; Helper functions

(defun in-docs? ()
  "Check if we are inside a string or comment"
  (nth 8 (syntax-ppss)))

(defun hashbang-line? ()
  "Does the current line contain a UNIX hashbang?"
  (and (eq 1 (line-number-at-pos))
       (save-excursion
         (move-beginning-of-line nil)
         (looking-at "#!"))))

(defun enclosing-paren ()
  "Return the opening parenthesis of the enclosing parens, or nil
if not inside any parens."
  (interactive)
  (let ((ppss (syntax-ppss)))
    (when (nth 1 ppss)
      (char-after (nth 1 ppss)))))



;;; General tweaks

(defun docs-. ()
  "Double space if setting tells us to"
  (if double-space-docs
      ".  "
    ". "))

(defun prog-mode-- ()
  "Handle exponent and negative number notation"
  (cond
   ;; Exponent notation, e.g. 1e-10: don't space
   ((looking-back "[0-9.]+[eE]") "-")

   ;; Space negative numbers as e.g. a = -1 (but don't space f(-1) or -1
   ;; alone at all). This will proabaly need to be major mode specific
   ;; eventually.
   ((looking-back "[=,:\*\+-/]") " -")
   ((looking-back "[[(]") "-")
   ((looking-back "^") "-")

   (t " - ")))

(defun prog-mode-/ ()
  "Handle path separator in UNIX hashbangs"
  ;; First / needs a space before it, rest don't need any spaces
  (cond ((and (hashbang-line?) (looking-back "#!")) " /")
        ((hashbang-line?) "/")
        (t " / ")))



;;; C/C++ mode tweaks

(apply #'add-rules-for-mode 'c-mode prog-mode-rules)
(add-rules-for-mode 'c-mode
                    (cons "->" "->")

                    ;; ternary operator
                    (cons "?" " ? ")
                    (cons ":" #'c-mode-:) ; (or case label)

                    ;; pointers
                    (cons "*" #'c-mode-*)
                    (cons "&" #'c-mode-&)
                    (cons "**" " **") ; pointer-to-pointer type

                    ;; increment/decrement
                    (cons "++" #'c-mode-++)
                    (cons "--" #'c-mode---)

                    ;; #include statements
                    (cons "<" #'c-mode-<)
                    (cons ">" #'c-mode->)
                    )


;; Use the same rules for c++
(puthash 'c++-mode (gethash 'c-mode mode-rules-table)
         mode-rules-table)

(defun c-mode-is-unary? ()
  "Try to guess if this is the unary form of an operator"
  (or (looking-back "[=,]\s*")
      (looking-back "^\s*")))

(defun c-types-regex ()
  (concat c-primitive-type-key "?"))

(defun c-mode-: ()
  "Handle the : part of ternary operator"
  (if (looking-back "\\?.+")
      " : "
    ":"))

(defun c-mode-++ ()
  "Handle ++ operator pre/postfix"
  (if (looking-back "[a-zA-Z0-9_]\s*")
      "++ "
    " ++"))

(defun c-mode--- ()
  "Handle -- operator pre/postfix"
  (if (looking-back "[a-zA-Z0-9_]\s*")
      "-- "
    " --"))

(defun c-mode-< ()
  "Handle #include brackets"
  (if (looking-back "#\s*include\s*")
      " <"
    ;; else
    " < "))

(defun c-mode-> ()
  "Handle #include brackets"
  (if (looking-back "#\s*include.*")
      ">"
    ;; else
    " > "))

(defun c-mode-& ()
  "Handle C address-of operator and reference types"
  (cond ((looking-back (c-types-regex)) " &")
        ((c-mode-is-unary?) " &")
        ((looking-back "(") "&")
        (t " & ")))

(defun c-mode-* ()
  "Handle C dereference operator and pointer types"
  (cond ((looking-back (c-types-regex)) " *")
        ((c-mode-is-unary?) " *")
        ((looking-back "(") "*")
        (t " * ")))



;;; Python mode tweaks

(apply #'add-rules-for-mode 'python-mode prog-mode-rules)
(add-rules-for-mode 'python-mode
                    (cons "**" #'python-mode-**)
                    (cons "*" #'python-mode-*)
                    (cons ":" #'python-mode-:)
                    (cons "//" " // ") ; integer division
                    (cons "=" #'python-mode-kwargs-=)
                    (cons "-" #'python-mode-negative-slices)
                    )

(defun python-mode-: ()
  "Handle python dict assignment"
  (if (and (not (in-string-p))
           (eq (enclosing-paren) ?\{))
      ": "
    ":"))

(defun python-mode-* ()
  "Handle python *args"
  ;; Can only occur after '(' ',' or on a new line, so just check for those.
  ;; If it's just after a comma then also insert a space before the *.
  (cond ((looking-back ",")  " *")
        ((looking-back "[(,^)][ \t]*")  "*")
        ;; Othewise act as normal
        (t  " * ")))

(defun python-mode-** ()
  "Handle python **kwargs"
  (cond ((looking-back ",") " **")
        ((looking-back "[(,^)][ \t]*") "**")
        (t " ** ")))

(defun python-mode-kwargs-= ()
  (if (eq (enclosing-paren) ?\()
      "="
    " = "))

(defun python-mode-negative-slices ()
  "Handle cases like a[1:-1], see issue #2."
  (if (and (eq (enclosing-paren) ?\[)
           (looking-back ":"))
      "-"
    (prog-mode--)))



;;; Other major mode tweaks

(puthash 'ruby-mode
         (add-rules prog-mode-rules
                    (cons "=~" " =~ ") ; regex equality
                    )
         mode-rules-table)

(puthash 'perl-mode
         (add-rules prog-mode-rules
                    (cons "=~" " =~ ") ; regex equality
                    )
         mode-rules-table)

(puthash 'cperl-mode (gethash 'cperl-mode mode-rules-table)
         mode-rules-table)

(puthash 'haskell-mode
         ;; Health warning: i haven't written much haskell recently so i'm
         ;; likely to have missed some things.
         (add-rules prog-mode-rules
                    (cons "." " . ") ; function composition
                    (cons "++" " ++ ") ; list concat
                    (cons "!!" " !! ") ; indexing
                    (cons "$" " $ ")
                    (cons "<-" " <- ")
                    (cons "->" " -> ")
                    (cons ":" nil) ; list constructor
                    (cons "::" " :: ") ; type specification
                    (cons "!=" nil) ; not-equal
                    )
         mode-rules-table)


) ; end of namespace

(provide 'electric-operator)

;;; electric-operator.el ends here