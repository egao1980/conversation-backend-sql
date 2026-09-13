(in-package #:conversation-backend-sql/tests)

(defun %text (turn)
  (llm-protocol:turn-text turn))

(defun %try-load-sqlite ()
  (or (find-package '#:sql-backend-sqlite3)
      (let ((ql (find-package :ql)))
        (when ql
          (ignore-errors
            (funcall (find-symbol "QUICKLOAD" ql) "sql-backend-sqlite3" :silent t)
            (find-package '#:sql-backend-sqlite3))))
      (ignore-errors
        (asdf:load-system "sql-backend-sqlite3" :verbose nil)
        (find-package '#:sql-backend-sqlite3))))

(deftest session-ddl-mentions-columns
  (ok (search "id" conversation-backend-sql:+sessions-table-ddl+))
  (ok (search "updated_at" conversation-backend-sql:+sessions-table-ddl+))
  (ok (search "CREATE TABLE" conversation-backend-sql:+sessions-table-ddl+))
  (ok (search "session_id" conversation-backend-sql:+turns-table-ddl+))
  (ok (search "seq" conversation-backend-sql:+turns-table-ddl+))
  (ok (search "role" conversation-backend-sql:+turns-table-ddl+))
  (ok (search "parts_json" conversation-backend-sql:+turns-table-ddl+))
  (ok (equal conversation-backend-sql:+session-ddl+
             (list conversation-backend-sql:+sessions-table-ddl+
                   conversation-backend-sql:+turns-table-ddl+))))

(deftest revision-metadata
  (let ((p (conversation-backend-sql:session-revision-plist)))
    (ok (equal "0001" (getf p :id)))
    (ok (equal "conversation-sessions" (getf p :name)))
    (ok (null (getf p :down-revision)))
    (ok (find conversation-backend-sql:+sessions-table-ddl+ (getf p :upgrade-sql)
              :test #'equal))))

(deftest encode-decode-text-parts
  (let* ((parts (list (llm-protocol:make-llm-text-part :text "hello")))
         (text (conversation-backend-sql:encode-turn-parts parts))
         (copy (conversation-backend-sql:decode-turn-parts text)))
    (ok (stringp text))
    (ok (search ":TEXT" (string-upcase text)))
    (ok (= 1 (length copy)))
    (ok (llm-protocol:llm-text-part-p (first copy)))
    (ok (equal "hello" (llm-protocol:llm-text-part-text (first copy))))))

(deftest encode-decode-mixed-parts
  (let* ((parts (list (llm-protocol:make-llm-text-part :text "hi")
                      (llm-protocol:make-llm-thinking-part :text "think" :signature "sig")
                      (llm-protocol:make-llm-tool-call-part :id "c1" :name "fn"
                                                            :arguments "{}")
                      (llm-protocol:make-llm-tool-result-part :id "c1" :name "fn"
                                                              :content "ok")
                      (llm-protocol:make-llm-image-part :url "https://x" :media-type "image/png")))
         (copy (conversation-backend-sql:decode-turn-parts
                (conversation-backend-sql:encode-turn-parts parts))))
    (ok (= 5 (length copy)))
    (ok (equal "hi" (llm-protocol:llm-text-part-text (first copy))))
    (ok (equal "think" (llm-protocol:llm-thinking-part-text (second copy))))
    (ok (equal "fn" (llm-protocol:llm-tool-call-part-name (third copy))))
    (ok (equal "ok" (llm-protocol:llm-tool-result-part-content (fourth copy))))
    (ok (equal "https://x" (llm-protocol:llm-image-part-url (fifth copy))))))

(deftest sql-session-roundtrip
  (if (not (%try-load-sqlite))
      (skip "sql-backend-sqlite3 not loadable")
      (uiop:with-temporary-file (:pathname path :prefix "conv-sql-" :type "sqlite")
        (let ((store (conversation-backend-sql:make-sql-session-store
                      :driver :sqlite3
                      :database-name (namestring path))))
          (unwind-protect
               (progn
                 (ok (null (conversation-protocol:load-session store "s")))
                 (conversation-protocol:save-session
                  store "s"
                  (list (llm-protocol:system-turn "sys")
                        (llm-protocol:user-turn "hi")
                        (llm-protocol:assistant-turn "yo")))
                 (let ((loaded (conversation-protocol:load-session store "s")))
                   (ok (= 3 (length loaded)))
                   (ok (equal '(:system :user :assistant)
                              (mapcar #'llm-protocol:llm-turn-role loaded)))
                   (ok (equal '("sys" "hi" "yo") (mapcar #'%text loaded))))
                 (conversation-protocol:save-session
                  store "s" (llm-protocol:user-turn "replaced"))
                 (ok (equal '("replaced")
                            (mapcar #'%text
                                    (conversation-protocol:load-session store "s"))))
                 (conversation-protocol:delete-session store "s")
                 (ok (null (conversation-protocol:load-session store "s")))
                 (ok (signals (conversation-protocol:delete-session store "s")
                              'conversation-protocol:conversation-session-not-found)))
            (conversation-backend-sql:close-sql-session-store store))))))

(deftest sql-session-persist-across-reconnect
  (if (not (%try-load-sqlite))
      (skip "sql-backend-sqlite3 not loadable")
      (uiop:with-temporary-file (:pathname path :prefix "conv-sql-" :type "sqlite")
        (let ((db (namestring path)))
          (let ((store (conversation-backend-sql:make-sql-session-store
                        :driver :sqlite3 :database-name db)))
            (conversation-protocol:save-session store "chat"
                                                (llm-protocol:user-turn "keep"))
            (conversation-backend-sql:close-sql-session-store store))
          (let ((store (conversation-backend-sql:make-sql-session-store
                        :driver :sqlite3 :database-name db)))
            (unwind-protect
                 (ok (equal '("keep")
                            (mapcar #'%text
                                    (conversation-protocol:load-session store "chat"))))
              (conversation-backend-sql:close-sql-session-store store)))))))

(deftest sql-store-with-buffer-memory
  (if (not (%try-load-sqlite))
      (skip "sql-backend-sqlite3 not loadable")
      (let ((store (conversation-backend-sql:make-sql-session-store
                    :driver :sqlite3 :database-name ":memory:")))
        (unwind-protect
             (let ((mem (conversation-protocol:make-buffer-memory
                         :store store :session "m")))
               (conversation-protocol:remember mem (llm-protocol:user-turn "a"))
               (ok (equal '("a" "b")
                          (mapcar #'%text
                                  (conversation-protocol:recall mem "b")))))
          (conversation-backend-sql:close-sql-session-store store)))))
