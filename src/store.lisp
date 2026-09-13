(in-package #:conversation-backend-sql)

(defclass sql-session-store (conversation-protocol:conversation-store)
  ((connection :initarg :connection :accessor sql-session-store-connection)
   (owns-connection :initarg :owns-connection :accessor sql-session-store-owns-connection
                    :initform nil)))

(defun %prin1-safe (value)
  (with-standard-io-syntax
    (let ((*print-readably* nil)
          (*print-circle* t)
          (*print-pretty* nil)
          (*package* (find-package :cl)))
      (prin1-to-string value))))

(defun %read-safe (string)
  (with-standard-io-syntax
    (let ((*read-eval* nil)
          (*package* (find-package :cl)))
      (read-from-string string))))

(defun %find-exported (package-name symbol-name)
  (let ((pkg (find-package package-name)))
    (when pkg
      (let ((sym (find-symbol symbol-name pkg)))
        (when (and sym (fboundp sym))
          sym)))))

(defun %bound-non-nil (package-name symbol-name)
  (let ((pkg (find-package package-name)))
    (when pkg
      (let ((sym (find-symbol symbol-name pkg)))
        (and sym (boundp sym) (symbol-value sym))))))

(defun part->sexp (part)
  (cond
    ((llm-protocol:llm-text-part-p part)
     (list :text (llm-protocol:llm-text-part-text part)))
    ((llm-protocol:llm-image-part-p part)
     (list :image
           :url (llm-protocol:llm-image-part-url part)
           :media-type (llm-protocol:llm-image-part-media-type part)
           :data (llm-protocol:llm-image-part-data part)))
    ((llm-protocol:llm-tool-call-part-p part)
     (list :tool-call
           :id (llm-protocol:llm-tool-call-part-id part)
           :name (llm-protocol:llm-tool-call-part-name part)
           :arguments (llm-protocol:llm-tool-call-part-arguments part)))
    ((llm-protocol:llm-tool-result-part-p part)
     (list :tool-result
           :id (llm-protocol:llm-tool-result-part-id part)
           :name (llm-protocol:llm-tool-result-part-name part)
           :content (llm-protocol:llm-tool-result-part-content part)
           :error-p (llm-protocol:llm-tool-result-part-error-p part)))
    ((llm-protocol:llm-thinking-part-p part)
     (list :thinking
           :text (llm-protocol:llm-thinking-part-text part)
           :signature (llm-protocol:llm-thinking-part-signature part)))
    (t (list :text (if (stringp part) part (princ-to-string part))))))

(defun sexp->part (form)
  (cond
    ((stringp form)
     (llm-protocol:make-llm-text-part :text form))
    ((and (consp form) (eq (car form) :text))
     (llm-protocol:make-llm-text-part :text (or (second form) "")))
    ((and (consp form) (eq (car form) :image))
     (let ((plist (cdr form)))
       (llm-protocol:make-llm-image-part
        :url (getf plist :url)
        :media-type (getf plist :media-type)
        :data (getf plist :data))))
    ((and (consp form) (eq (car form) :tool-call))
     (let ((plist (cdr form)))
       (llm-protocol:make-llm-tool-call-part
        :id (getf plist :id)
        :name (getf plist :name)
        :arguments (or (getf plist :arguments) "{}"))))
    ((and (consp form) (eq (car form) :tool-result))
     (let ((plist (cdr form)))
       (llm-protocol:make-llm-tool-result-part
        :id (getf plist :id)
        :name (getf plist :name)
        :content (or (getf plist :content) "")
        :error-p (getf plist :error-p))))
    ((and (consp form) (eq (car form) :thinking))
     (let ((plist (cdr form)))
       (llm-protocol:make-llm-thinking-part
        :text (or (getf plist :text) "")
        :signature (getf plist :signature))))
    (t (llm-protocol:make-llm-text-part :text (princ-to-string form)))))

(defun %encode-payload (value)
  "Encode VALUE as a string. Soft-use serdes-protocol / json-protocol if bound."
  (let ((serdes (and (%bound-non-nil '#:serdes-protocol "*SERDES-BACKEND*")
                     (%find-exported '#:serdes-protocol "ENCODE")))
        (json (and (%bound-non-nil '#:json-protocol "*JSON-BACKEND*")
                   (%find-exported '#:json-protocol "ENCODE"))))
    (or (when serdes
          (ignore-errors (funcall serdes value)))
        (when json
          (ignore-errors (funcall json value)))
        (%prin1-safe value))))

(defun %decode-payload (string)
  "Decode a string from %ENCODE-PAYLOAD. Soft-use serdes / json if bound."
  (let ((serdes (and (%bound-non-nil '#:serdes-protocol "*SERDES-BACKEND*")
                     (%find-exported '#:serdes-protocol "DECODE")))
        (json (and (%bound-non-nil '#:json-protocol "*JSON-BACKEND*")
                   (%find-exported '#:json-protocol "DECODE"))))
    (or (when serdes
          (ignore-errors (funcall serdes string)))
        (when json
          (ignore-errors (funcall json string)))
        (%read-safe string))))

(defun encode-turn-parts (parts)
  "Serialize PARTS (llm-part list) as a readable sexp string by default."
  (%encode-payload (mapcar #'part->sexp parts)))

(defun decode-turn-parts (string)
  "Rehydrate an llm-part list from ENCODE-TURN-PARTS."
  (let ((data (if (stringp string)
                  (%decode-payload string)
                  string)))
    (mapcar #'sexp->part (if (listp data) data (list data)))))

(defun %role-string (role)
  (string-downcase (symbol-name role)))

(defun %parse-role (value)
  (let ((s (string value)))
    (cond
      ((string-equal s "system") :system)
      ((string-equal s "assistant") :assistant)
      ((string-equal s "tool") :tool)
      (t :user))))

(defun %now-stamp ()
  (format nil "~d" (get-universal-time)))

(defun %exec (store sql &optional params)
  (sql-protocol:execute (sql-session-store-connection store) sql params))

(defun %fetch (store sql &optional params)
  (sql-protocol:fetch (%exec store sql params)))

(defun %fetch-all (store sql &optional params)
  (sql-protocol:fetch-all (%exec store sql params)))

(defun %row-get (row key)
  (or (getf row key)
      (getf row (intern (string-upcase (string key)) :keyword))))

(defmethod ensure-session-schema ((store sql-session-store))
  (dolist (sql +session-ddl+)
    (%exec store sql))
  store)

(defmethod ensure-session-schema ((connection sql-protocol:sql-connection))
  (dolist (sql +session-ddl+)
    (sql-protocol:execute connection sql))
  connection)

(defun make-sql-session-store (&key connection
                                    (driver :sqlite3)
                                    database-name
                                    (ensure-schema t))
  (let* ((owns (null connection))
         (conn (or connection
                   (apply #'sql-protocol:connect
                          :driver driver
                          (when database-name
                            (list :database-name database-name)))))
         (store (make-instance 'sql-session-store
                               :connection conn
                               :owns-connection owns)))
    (when ensure-schema
      (ensure-session-schema store))
    store))

(defun use-sql-session-store (&rest args &key &allow-other-keys)
  (setf conversation-protocol:*conversation-store*
        (apply #'make-sql-session-store args)))

(defun close-sql-session-store (store)
  (when (and (sql-session-store-owns-connection store)
             (sql-session-store-connection store))
    (ignore-errors (sql-protocol:disconnect (sql-session-store-connection store)))
    (setf (sql-session-store-connection store) nil
          (sql-session-store-owns-connection store) nil))
  store)

(defun %turn-from-row (row)
  (llm-protocol:make-llm-turn
   :role (%parse-role (%row-get row :role))
   :parts (decode-turn-parts (%row-get row :parts_json))))

(defmethod conversation-protocol:load-session ((store sql-session-store) session)
  (let* ((sid (conversation-protocol:coerce-session session))
         (rows (%fetch-all store
                           "SELECT seq, role, parts_json FROM turns
 WHERE session_id = ? ORDER BY seq"
                           (list sid))))
    (mapcar #'%turn-from-row rows)))

(defmethod conversation-protocol:save-session ((store sql-session-store) session turns)
  (let ((sid (conversation-protocol:coerce-session session))
        (normalized (llm-protocol:coerce-turns turns))
        (stamp (%now-stamp)))
    (sql-protocol:with-transaction ((sql-session-store-connection store))
      (%exec store "DELETE FROM turns WHERE session_id = ?" (list sid))
      (%exec store "DELETE FROM sessions WHERE id = ?" (list sid))
      (%exec store "INSERT INTO sessions (id, updated_at) VALUES (?, ?)"
             (list sid stamp))
      (loop for turn in normalized
            for seq from 1
            do (%exec store
                      "INSERT INTO turns (session_id, seq, role, parts_json)
VALUES (?, ?, ?, ?)"
                      (list sid
                            seq
                            (%role-string (llm-protocol:llm-turn-role turn))
                            (encode-turn-parts (llm-protocol:llm-turn-parts turn))))))
    store))

(defmethod conversation-protocol:delete-session ((store sql-session-store) session)
  (let ((sid (conversation-protocol:coerce-session session)))
    (if (%fetch store "SELECT id FROM sessions WHERE id = ?" (list sid))
        (sql-protocol:with-transaction ((sql-session-store-connection store))
          (%exec store "DELETE FROM turns WHERE session_id = ?" (list sid))
          (%exec store "DELETE FROM sessions WHERE id = ?" (list sid))
          store)
        (restart-case
            (error 'conversation-protocol:conversation-session-not-found
                   :session sid
                   :message (format nil "unknown session ~s" sid))
          (continue ()
            :report "Skip missing session"
            nil)
          (use-value (value)
            :report "Return a supplied value"
            (return-from conversation-protocol:delete-session value))))))
