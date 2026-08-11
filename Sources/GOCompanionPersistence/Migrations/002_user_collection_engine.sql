ALTER TABLE pokemon ADD COLUMN revision INTEGER NOT NULL DEFAULT 1;

ALTER TABLE observations ADD COLUMN pokemon_id TEXT REFERENCES pokemon(id);
ALTER TABLE observations ADD COLUMN provenance_json TEXT;
CREATE INDEX observations_pokemon_time_idx ON observations(pokemon_id, observed_at);

ALTER TABLE collection_history ADD COLUMN reason TEXT;
ALTER TABLE collection_history ADD COLUMN source TEXT NOT NULL DEFAULT 'legacy';
ALTER TABLE collection_history ADD COLUMN changes_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE collection_history ADD COLUMN provenance_json TEXT;
ALTER TABLE collection_history ADD COLUMN correlation_id TEXT;
CREATE UNIQUE INDEX history_correlation_event_idx ON collection_history(correlation_id, id);

CREATE TABLE pokemon_internal_tags (
  pokemon_id TEXT NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(pokemon_id, tag)
);
CREATE INDEX internal_tags_lookup_idx ON pokemon_internal_tags(tag, pokemon_id);

CREATE TABLE pokemon_roles (
  pokemon_id TEXT NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  assigned_at TEXT NOT NULL,
  PRIMARY KEY(pokemon_id, role)
);
CREATE INDEX pokemon_roles_lookup_idx ON pokemon_roles(role, pokemon_id);

CREATE TABLE recommended_go_tags (
  pokemon_id TEXT NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  recommendation_state TEXT NOT NULL,
  reason TEXT NOT NULL,
  appears_applied INTEGER NOT NULL DEFAULT 0,
  user_confirmation TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  source_version TEXT NOT NULL,
  PRIMARY KEY(pokemon_id, tag)
);
CREATE INDEX recommended_tags_lookup_idx ON recommended_go_tags(tag, recommendation_state, pokemon_id);

CREATE TRIGGER pokemon_status_insert_check
BEFORE INSERT ON pokemon
WHEN NEW.status NOT IN (
  'active', 'pendingReview', 'pendingRemoval',
  'archivedTransferred', 'archivedTraded', 'archivedOther'
)
BEGIN
  SELECT RAISE(ABORT, 'invalid collection status');
END;

CREATE TRIGGER pokemon_status_update_check
BEFORE UPDATE OF status ON pokemon
WHEN NEW.status NOT IN (
  'active', 'pendingReview', 'pendingRemoval',
  'archivedTransferred', 'archivedTraded', 'archivedOther'
)
BEGIN
  SELECT RAISE(ABORT, 'invalid collection status');
END;

CREATE TRIGGER collection_history_immutable_update
BEFORE UPDATE ON collection_history
BEGIN
  SELECT RAISE(ABORT, 'collection history is immutable');
END;

CREATE TRIGGER collection_history_immutable_delete
BEFORE DELETE ON collection_history
BEGIN
  SELECT RAISE(ABORT, 'collection history is immutable');
END;
