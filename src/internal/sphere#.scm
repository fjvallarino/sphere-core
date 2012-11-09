;;; Copyright (c) 2012, Alvaro Castro-Castilla. All rights reserved.
;;; Sphere (module system)

;-------------------------------------------------------------------------------
; Sphere
;-------------------------------------------------------------------------------

(define^ default-src-directory
  (make-parameter "src/"))

(define^ default-build-directory
  (make-parameter "build/"))

(define^ default-lib-directory
  (make-parameter "lib/"))

(define^ default-scm-extension
  (make-parameter ".scm"))

(define^ default-o-extension
  (make-parameter ".o1"))

(define^ default-c-extension
  (make-parameter ".o1.c"))

(define^ config-file
  (make-parameter "config.scm"))

;;; Read current sphere config data
;;; Returns null list if no config data found
(define^ %current-config
  (let ((cached #f))
    (lambda ()
      (or cached
          (begin
            (set! cached
                  (with-exception-catcher
                   (lambda (e) (if (no-such-file-or-directory-exception? e)
                              ;; If config file not found try to find global %paths variable
                              (with-exception-catcher
                               (lambda (e2) (if (unbound-global-exception? e2)
                                           '()
                                           (raise e2)))
                               ;; inject global %paths variable if no config file found
                               (lambda () `((paths: ,@%system-paths))))
                              (raise e)))
                   (lambda () (call-with-input-file (config-file) read-all))))
            cached)))))

(define^ %current-sphere
  (make-parameter
   (let ((current-sphere-info (assq sphere: (%current-config))))
     (if current-sphere-info
         (string->symbol (cadr current-sphere-info))
         #f))))

(define^ (%sphere-system-path sphere)
  (string-append "~~spheres/" (symbol->string sphere) "/"))

(define^ (%sphere-path sphere)
  (let ((paths (%paths)))
    (if sphere
        ;; First try with custom paths: in config file
        (uif (assq (string->keyword (symbol->string sphere)) paths)
             (string-append (path-strip-trailing-directory-separator (cadr ?it)) "/")
             ;; Otherwise, try system-installed spheres
             (if (file-exists? (%sphere-system-path sphere))
                 (%sphere-system-path sphere)
                 (error (string-append "Sphere not found: " (object->string sphere) " -- Please set a path in config file or install the sphere in the ~~spheres directory"))))
        #f)))

(define^ (%paths)
  (let ((paths (uif (assq paths: (%current-config))
                    (cdr ?it)
                    '())))
    (uif (%current-sphere)
         (cons
          (list (symbol->keyword ?it) (current-directory))
          paths)
         paths)))

;;; Used for getting a specific sphere config data
(define^ %sphere-config
  (let ((config-dict '()))
    (lambda (sphere)
      (if sphere
          (uif (assq sphere config-dict)
               (cadr ?it)
               (let ((new-pair (list
                                sphere
                                (with-exception-catcher
                                 (lambda (e) (if (no-such-file-or-directory-exception? e)
                                            (error (string-append "Sphere \"" (symbol->string sphere) "\" doesn't have a con
fig.scm file"))
                                            (raise e)))
                                 (lambda () (call-with-input-file
                                           (string-append (or (%sphere-path sphere) "")
                                                          (config-file))
                                         read-all))))))
                 (set! config-dict
                       (cons new-pair config-dict))
                 (cadr new-pair)))
          '()))))

;;; Get dependencies of sphere's modules
(define^ (%sphere-dependencies sphere)
  (let ((expand-cond-features
         (lambda (deps)
           (let ((any-eq? (lambda (k l)
                            (let recur ((l l))
                              (cond ((null? l) #f)
                                    ((eq? k (car l)) #t)
                                    (else (recur (cdr l))))))))
             (let expand-cond-features ((deps deps))
               (cond ((null? deps) '())
                     ((not (pair? deps)) deps)
                     ((eq? 'cond-expand (car deps))
                      ;; cond-expand found
                      (let find-condition ((conditions (cdr deps)))
                        (cond ((null? conditions)
                               (error "cond-expand in dependencies not met"))
                              ((not (pair? (car conditions)))
                               (error "incorrect cond-expand syntax"))
                              ((and (symbol? (caar conditions))
                                    (any-eq? (caar conditions) ##cond-expand-features))
                               (cadar conditions))
                              ((and (symbol? (caar conditions))
                                    (eq? (caar conditions) 'else))
                               (cadar conditions))
                              ((and (pair? (caar conditions))
                                    (eq? (caaar conditions) 'or))
                               (error "OR clauses in dependencies not implemented yet"))
                              ((and (pair? (caar conditions))
                                    (eq? (caaar conditions) 'and))
                               (error "AND clauses in dependencies not implemented yet"))
                              ((and (pair? (caar conditions))
                                    (eq? (caaar conditions) 'not))
                               (error "NOT clauses in dependencies not implemented yet"))
                              ((and (pair? (caar conditions)))
                               (error "incorrect cond-expand syntax: must use OR, AND, NOT lists or single symbols"))
                              (else
                               (find-condition (cdr conditions))))))
                     (else (cons (expand-cond-features (car deps))
                                 (expand-cond-features (cdr deps)))))))))
        (expand-wildcards
         (lambda (deps)
           (map (lambda (e)
                  (let ((module (car e))
                        (rest (cdr e)))
                    (cons
                     (cond
                      ((%module-reduced-form? module) (%module-normalize module override-sphere: sphere))
                      ((eq? '= (car module)) (cons (symbol->keyword sphere) (cdr module)))
                      (else module))
                     rest)))
                deps))))
    (aif it (assq dependencies: (%sphere-config sphere))
         (expand-wildcards
          (expand-cond-features
           (cdr it)))
         '())))

;-------------------------------------------------------------------------------
; Module
;-------------------------------------------------------------------------------

(define^ (%make-module #!key (sphere #f) id (version '()))
  (if sphere
      (append (list (->keyword sphere)
                    (->symbol id)
                    version: version))
      (->symbol id)))

;;; Signal error when module has a wrong format
(define^ (module-error module)
  (error "Error parsing module directive (wrong module format): " module))

;;; Module structure: (sphere: module-id [version: '(list-of-version-features)])
(define^ %module-reduced-form? symbol?)

(define^ (%module-normal-form? module)
  (and (list? module)
       (or (keyword? (car module))
           (eq? '= (car module))) ; Wildcard = represents the "this" sphere
       (not (null? (cdr module)))
       (symbol? (cadr module))
       (unless (null? (cddr module))
               (and (eq? version: (caddr module))
                    (list? (cadddr module))))))

(define^ (%module-normalize module #!key (override-sphere #f))
  (%make-module sphere: (if override-sphere override-sphere (%module-sphere module))
                id: (%module-id module)
                version: (%module-version module)))

(define^ (%module? module)
  (or (%module-reduced-form? module)
      (%module-normal-form? module)))

(define^ (%module-sphere module)
  (assure (%module? module) (module-error module))
  (if (%module-normal-form? module)
      (keyword->symbol (car module))
      (%current-sphere)))

(define^ (%module-id module)
  (assure (%module? module) (module-error module))
  (if (%module-normal-form? module)
      (cadr module)
      module))

(define^ (%module-version module)
  (assure (%module? module) (module-error module))
  (if (%module-normal-form? module)
      ;; Search for version: from the third element on
      (let ((version (memq version: (cddr module))))
        (if version
            (cadr version)
            '()))
      '()))

(define^ (%module-path module)
  (let ((sphere (%module-sphere module)))
    (if sphere
        (%sphere-path sphere)
        "")))

(define^ (%module-path-src module)
  (string-append (%module-path module) (default-src-directory)))

(define^ (%module-path-lib module)
  (string-append (%module-path module) (default-lib-directory)))

;;; Module versions identify debug, architecture or any compiled-in features
;;; Normalizes removing duplicates and sorting alphabetically
(define^ (%version->string version-symbol-list)
  (letrec ((delete-duplicates
            (lambda (l)
              (cond ((null? l)
                     '())
                    ((member (car l) (cdr l))
                     (delete-duplicates (cdr l)))
                    (else
                     (cons (car l) (delete-duplicates (cdr l)))))))
           (insertion-sort
            (letrec ((insert
                      (lambda (x lst)
                        (if (null? lst)
                            (list x)
                            (let ((y (car lst))
                                  (ys (cdr lst)))
                              (if (string<=? x y)
                                  (cons x lst)
                                  (cons y (insert x ys))))))))
              (lambda (lst)
                (if (null? lst)
                    '()
                    (insert (car lst)
                            (insertion-sort (cdr lst))))))))
    (apply string-append (map (lambda (s) (string-append s "___"))
                              (insertion-sort
                               (map symbol->string
                                    (delete-duplicates version-symbol-list)))))))

;;; Transforms / into _
(define^ (%module-flat-name module)
  (assure (%module? module) (module-error module))
  (let ((name (string-copy (symbol->string (%module-id module)))))
    (let recur ((i (-- (string-length name))))
      (if (= i 0)
          name
          (begin (when (eq? (string-ref name i) #\/)
                       (string-set! name i #\_))
                 (recur (-- i)))))))

(define^ (%module-filename-scm module)
  (assure (%module? module) (module-error module))
  (string-append (symbol->string (%module-id module))
                 (default-scm-extension)))

(define^ (%module-filename-c module #!key (version '()))
  (assure (%module? module) (module-error module))
  (string-append (if (null? version)
                     (%version->string (%module-version module))
                     (%version->string version))
                 (symbol->string (%module-sphere module))
                 "__"
                 (%module-flat-name module)
                 (default-c-extension)))

(define^ (%module-filename-o module #!key (version '()))
  (assure (%module? module) (module-error module))
  (string-append (if (null? version)
                     (%version->string (%module-version module))
                     (%version->string version))
                 (symbol->string (%module-sphere module))
                 "__"
                 (%module-flat-name module)
                 (default-o-extension)))

;;; Module dependecies, as directly read from the %config
(define^ (%module-dependencies module)
  (assure (%module? module) (module-error module))
  (assq (%module-id module) (%sphere-dependencies (%module-sphere module))))

(define^ (%module-dependencies-select type)
  (letrec ((find-normalized
            (lambda (module sphere sphere-deps)
              (cond ((null? sphere-deps) #f)
                    ;; Check if module is from this sphere
                    ((not (eq? (%module-sphere (caar sphere-deps)) sphere))
                     (error (string-append "Dependency lists can't be done for non-local modules -> change " (config-file) " (tip: you can use = to identify local spheres)")))
                    ;; First check for the right version of the module
                    ((equal? (%module-normalize module)
                             (%module-normalize (caar sphere-deps)
                                                override-sphere: sphere))
                     (car sphere-deps))
                    (else (find-normalized module sphere (cdr sphere-deps))))))
           (find-unversioned
            (lambda (module sphere sphere-deps)
              (cond ((null? sphere-deps) #f)
                    ;; If not found, assume that unversioned dependencies can be used (only module is checked)
                    ((equal? (cadr (%module-normalize module))
                             (cadr (%module-normalize (caar sphere-deps)
                                                      override-sphere: sphere)))
                     (display (string-append "*** WARNING -- No versioned dependencies found, using unversioned modules for "
                                             (object->string module)
                                             "\n"))
                     (car sphere-deps))
                    (else (find-unversioned module sphere (cdr sphere-deps)))))))
    (lambda (module)
      (assure (%module? module) (module-error module))
      (let ((module-sphere (%module-sphere module))
            (get-dependency-list (lambda (l) (aif it (assq type (cdr l)) (cdr it) '()))))
        (aif this (find-normalized module module-sphere (%sphere-dependencies module-sphere))
             (get-dependency-list this)
             (aif that (find-unversioned module module-sphere (%sphere-dependencies module-sphere))
                  (get-dependency-list that)
                  '()))))))

(define^ (%module-dependencies-to-include module)
  ((%module-dependencies-select 'include) module))

(define^ (%module-dependencies-to-load module)
  ((%module-dependencies-select 'load) module))

;;; Gets the full tree of dependencies, building a list in the right order
(define^ (%module-deep-dependencies-select type)
  (lambda (module)
    (let ((deps '()))
      (let recur ((module module))
        (for-each recur ((%module-dependencies-select type) module))
        (unless (member (%module-normalize module) deps)
                (set! deps (cons (%module-normalize module) deps))))
      (reverse deps))))

(define^ (%module-deep-dependencies-to-load module)
  ((%module-deep-dependencies-select 'load) module))

;-------------------------------------------------------------------------------
; Utils
;-------------------------------------------------------------------------------

;;; Builds a new list of modules merging two lists
;;; Not optimized
(define^ (%merge-module-lists dep1 dep2)
  (letrec ((delete-duplicates
            (lambda (l) (cond ((null? l) '())
                         ((member (car l) (cdr l)) (delete-duplicates (cdr l)))
                         (else (cons (car l) (delete-duplicates (cdr l))))))))
    ;; We work on reversed list to keep the first occurence
    (reverse (delete-duplicates (reverse (append dep1 dep2))))))

;;; Select modules from a list belonging to a sphere
(define^ (%select-modules modules spheres)
  (let* ((select (if (pair? spheres) spheres (list spheres)))
         (any-eq? (lambda (k l)
                    (let recur ((l l))
                      (cond ((null? l) #f)
                            ((eq? k (car l)) #t)
                            (else (recur (cdr l))))))))
    (let recur ((output modules))
      (cond ((null? output) '())
            ((any-eq? (%module-sphere (car output)) select)
             (cons (car output) (recur (cdr output))))
            (else (recur (cdr output)))))))

;-------------------------------------------------------------------------------
; Including and loading
;-------------------------------------------------------------------------------

;;; Is there a header for this module? If so, return the header module
(define^ (%module-header module)
  (let ((header-module (%make-module
                        sphere: (%module-sphere module)
                        id: (string->symbol (string-append (symbol->string (%module-id module)) "#"))
                        version: (%module-version module))))
    (when (file-exists?
           (string-append (%module-path-src header-module)
                          (%module-filename-scm header-module)))
          header-module)))

;;; Main include macro, doesn't load dependencies
(define-macro (%include . module)
  (let* ((module (if (null? (cdr module))
                     (car module)
                     module))
         (module-name (symbol->string (%module-id module)))
         (sphere (%module-sphere module))
         (verbose #t))
    (assure (%module? module) (module-error module))
    (if sphere
        (let ((include-file (string-append (%module-path-src module) (%module-filename-scm module))))
          (if verbose (display (string-append "-- including: " module-name " -- (" (symbol->string sphere) ")" "\n")))
          `(include ,include-file))
        (begin
          (if verbose (display (string-append "-- loading -- " module-name ")\n")))
          `(include ,(%module-filename-scm module))))))

;;; Load module and dependencies
(define^ %load-module-and-dependencies
  (let ((*%loaded-modules* '()))
    (lambda (root-module #!key
                    (verbose #f)
                    (omit-root #f))
      (let recur ((module root-module))
        (define (load-single-module module)
          (let ((sphere (%module-sphere module)))
            (if sphere
                (begin (if verbose
                           (display (string-append "-- loading -- "
                                                   (object->string module)
                                                   "\n")))
                       (let ((file-o (string-append (%sphere-path sphere) (default-lib-directory) (%module-filename-o module)))
                             (file-scm (string-append (%sphere-path sphere) (default-src-directory) (%module-filename-scm module))))
                         (pv file-o)
                         (cond ((file-exists? file-o)
                                (load file-o))
                               ((file-exists? file-scm)
                                (load file-scm))
                               (else
                                (error (string-append "Module: "
                                                      (object->string module)
                                                      " cannot be found in current sphere's path"))))
                         (set! *%loaded-modules* (cons (%module-normalize module) *%loaded-modules*))))
                (begin (if verbose
                           (display (string-append "-- loading -- " (object->string module) "\n")))
                       (load (%module-filename-scm module))))))
        (if (not (member (%module-normalize module) *%loaded-modules*))
            (begin (for-each recur (%module-dependencies-to-load module))
                   (unless (and omit-root (equal? root-module module))
                           (load-single-module module))))))))

;;; Load only module dependencies, do not load the module
(define-macro (%load-module-dependencies . module)
  (let ((module (if (null? (cdr module))
                    (car module)
                    module)))
    (assure (%module? module) (module-error module))
    (%load-module-and-dependencies module omit-root: #t verbose: #t)))

;;; Main load macro, loads dependencies
(define-macro (%load . module)
  (let* ((module (if (null? (cdr module))
                     (car module)
                     module))
         (header-module (%module-header module)))
    (assure (%module? module) (module-error module))
    (when header-module
          (eval `(##namespace (,(symbol->string (%module-id header-module)))))
          (eval '(##include "~~lib/gambit#.scm"))
          (eval `(##include ,(string-append (%module-path-src header-module)
                                            (%module-filename-scm header-module))))
          (display (string-append "-- including header -- " (object->string include-module) "\n")))
    (%load-module-and-dependencies module verbose: #t)))
