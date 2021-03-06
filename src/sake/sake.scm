;;; @file sake.scm
;;; this file is just a little wrapper around the function
;;; sake in sake/common.scm
;;; @author francesco bracchi <frbracch@gmail.com>

(##namespace ("sake#"))
(##include "~~/lib/gambit#.scm")
(##include "sakelib.scm")
(##include "../internal/arguments.scm")

(define *help* #<<end-help-string

Usage: sake [--file <sake-file>] [<initial-task> <tasks>]

Arguments:
    <sake-file> is the file containing tasks description (defaults to sakefile.scm)
    <initial-task> is the first task to be run
    <tasks> follow the same order as in the command line

end-help-string
)

(define (main args)
  (define *options*
    '((#\h 0 "help")
      (#\f 1 "file")
      (#\X 0 "no-extensions")))
  (define (process-tasks explicit-tasks? opts args)
    (define help #f)
    (define file "sakefile.scm")
    (define no-extensions #f)
    (handle-opts!
     opts
     `(("help"
        ,@(lambda (val)
            (println *help*)
            (exit 0)))
       ("file"
        ,@(lambda (val)
            (set! file (with-input-from-string val read))))
       ("no-extensions"
        ,@(lambda (val)
            (set! no-extensions #t)))))
    (if explicit-tasks? (ensure-args! args))
    (sake file: file tasks: (map string->symbol args) extensions: (not no-extensions)))
  (parse-arguments
   args
   (lambda (args-sans-opts opts)
     (if (or (null? (cdr args-sans-opts))
             (char=? #\- (string-ref (cadr args-sans-opts) 0)))
         (process-tasks #f
                        opts
                        '("all"))
         (process-tasks #t
                        opts
                        (cdr args-sans-opts))))
   *options*))

(main (command-line))
