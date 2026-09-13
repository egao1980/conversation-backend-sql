(in-package #:conversation-backend-sql)

;;; Wave-1 applies DDL via ENSURE-SESSION-SCHEMA (sql-protocol:execute).
;;; sql-migrate 0.1.0 is an in-memory SCRIPT-DIRECTORY — register
;;; MAKE-SESSION-REVISION when sql-orm + sql-migrate are loaded.

(defparameter +session-revision-id+ "0001")
(defparameter +session-revision-name+ "conversation-sessions")

(defparameter +sessions-table-ddl+
  "CREATE TABLE IF NOT EXISTS sessions (
  id TEXT NOT NULL PRIMARY KEY,
  updated_at TEXT NOT NULL
)")

(defparameter +turns-table-ddl+
  "CREATE TABLE IF NOT EXISTS turns (
  session_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  role TEXT NOT NULL,
  parts_json TEXT NOT NULL,
  PRIMARY KEY (session_id, seq)
)")

(defparameter +session-ddl+
  (list +sessions-table-ddl+ +turns-table-ddl+))

(defun session-revision-plist ()
  "sql-migrate-shaped revision metadata (upgrade SQL is +SESSION-DDL+)."
  (list :id +session-revision-id+
        :name +session-revision-name+
        :down-revision nil
        :upgrade-sql +session-ddl+
        :downgrade-sql (list "DROP TABLE IF EXISTS turns"
                             "DROP TABLE IF EXISTS sessions")))

(defgeneric ensure-session-schema (target)
  (:documentation "CREATE TABLE IF NOT EXISTS sessions + turns (standard SQL)."))

(defun make-session-revision (&optional dir)
  "Return a sql-orm SCHEMA-MIGRATION when sql-orm is loaded; otherwise the
   revision plist. If DIR is a sql-migrate SCRIPT-DIRECTORY, register it."
  (let* ((orm (find-package '#:sql-orm))
         (migrate (find-package '#:sql-migrate))
         (meta (session-revision-plist))
         (rev
          (if orm
              (let ((class (find-symbol "SCHEMA-MIGRATION" orm)))
                (if class
                    (make-instance class
                                   :name +session-revision-name+
                                   :revision +session-revision-id+
                                   :down-revision nil
                                   :ops nil)
                    meta))
              meta)))
    (when (and dir migrate)
      (let ((reg (find-symbol "REGISTER-REVISION" migrate)))
        (when (and reg (fboundp reg))
          (funcall reg dir rev))))
    rev))
