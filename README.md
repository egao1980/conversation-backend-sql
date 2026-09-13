# conversation-backend-sql

[`sql-protocol`](https://github.com/egao1980/sql-protocol) session store for [`conversation-protocol`](https://github.com/egao1980/conversation-protocol). Standard SQL only — same DDL on `sql-backend-sqlite3` (personal) and `sql-backend-postgres` (corporate).

```lisp
(asdf:load-system "sql-backend-sqlite3")
(asdf:load-system "conversation-backend-sql")

(let ((store (conversation-backend-sql:make-sql-session-store
              :driver :sqlite3 :database-name ":memory:")))
  (stack-conversation:save-session store "chat"
                                   (list (stack-llm:user-turn "hi")
                                         (stack-llm:assistant-turn "hello")))
  (stack-conversation:load-session store "chat")
  (conversation-backend-sql:close-sql-session-store store))
```

Pass an existing `sql-connection` with `:connection` if you already own the handle.

| Piece | Notes |
|-------|--------|
| `sql-session-store` | Implements `load-session` / `save-session` / `delete-session` |
| `sessions (id, updated_at)` + `turns (session_id, seq, role, parts_json)` | Wave-1 schema |
| `+session-ddl+` | List of `CREATE TABLE IF NOT EXISTS` strings |
| `ensure-session-schema` | Applies `+session-ddl+` via `sql-protocol:execute` |
| `encode-turn-parts` / `decode-turn-parts` | Readable sexp string by default. Soft-use `serdes-protocol` / `json-protocol` when `*serdes-backend*` / `*json-backend*` is bound. No hard serdes dep. |
| `migrations/0001-sessions.lisp` | sql-migrate-shaped revision (`make-session-revision`) |

Missing `delete-session` → `conversation-session-not-found` (`continue` / `use-value`), same as the in-memory store.

## Tests

Encode/decode + DDL strings always run. Live SQLite (tmpdir) runs when `sql-backend-sqlite3` is loadable.

## License

MIT — see [LICENSE](LICENSE).
