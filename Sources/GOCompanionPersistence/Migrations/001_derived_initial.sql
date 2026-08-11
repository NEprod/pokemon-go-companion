CREATE TABLE derived_entries (
  cache_kind TEXT NOT NULL,
  subject_key TEXT NOT NULL,
  input_versions_json TEXT NOT NULL,
  engine_version TEXT NOT NULL,
  payload BLOB NOT NULL,
  created_at TEXT NOT NULL,
  last_accessed_at TEXT NOT NULL,
  PRIMARY KEY(cache_kind, subject_key, input_versions_json, engine_version)
);
CREATE INDEX derived_access_idx ON derived_entries(last_accessed_at);

CREATE TABLE invalidation_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,
  old_version TEXT,
  new_version TEXT NOT NULL,
  invalidated_at TEXT NOT NULL,
  affected_count INTEGER NOT NULL DEFAULT 0
);
