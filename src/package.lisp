(defpackage #:conversation-backend-sql
  (:use #:cl)
  (:export #:sql-session-store
           #:make-sql-session-store
           #:use-sql-session-store
           #:close-sql-session-store
           #:sql-session-store-connection

           #:+session-ddl+
           #:+sessions-table-ddl+
           #:+turns-table-ddl+
           #:+session-revision-id+
           #:+session-revision-name+
           #:ensure-session-schema
           #:make-session-revision
           #:session-revision-plist

           #:encode-turn-parts
           #:decode-turn-parts))

(in-package #:conversation-backend-sql)
