;;;; sql-migrate revision 0001 — conversation sessions + turns
;;;;
;;;; sql-migrate 0.1.0 stores revisions in a SCRIPT-DIRECTORY (in-memory);
;;;; there is no on-disk runner format yet. Register this revision with:
;;;;
;;;;   (ql:quickload '(:sql-migrate :sql-orm :conversation-backend-sql))
;;;;   (let ((dir (sql-migrate:make-script-directory)))
;;;;     (sql-migrate:register-revision
;;;;      dir (conversation-backend-sql:make-session-revision)))
;;;;
;;;; Wave-1 applies the same DDL via ENSURE-SESSION-SCHEMA / +session-ddl+
;;;; (no hard dependency on sql-migrate or sql-orm).

(in-package #:conversation-backend-sql)

(defparameter +revision-0001+
  (session-revision-plist))
