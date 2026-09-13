(defsystem "conversation-backend-sql"
  :version "0.1.0"
  :description "sql-protocol session store for conversation-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("conversation-protocol" "sql-protocol")
  :properties (:cl-repo
               (:ci (:with ("sql-backend-sqlite3"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "schema")
               (:file "store"))
  :in-order-to ((test-op (test-op "conversation-backend-sql/tests"))))

(defsystem "conversation-backend-sql/tests"
  :depends-on ("conversation-backend-sql" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "store-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
