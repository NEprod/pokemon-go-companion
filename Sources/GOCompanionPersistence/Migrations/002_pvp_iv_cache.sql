CREATE TABLE pvp_iv_cache_metadata (
  subject_key TEXT NOT NULL,
  knowledge_version TEXT NOT NULL,
  engine_version TEXT NOT NULL,
  league_configuration_key TEXT NOT NULL,
  generated_at TEXT NOT NULL,
  PRIMARY KEY(subject_key, knowledge_version, engine_version)
);
CREATE INDEX pvp_iv_cache_version_idx
  ON pvp_iv_cache_metadata(knowledge_version, engine_version);
