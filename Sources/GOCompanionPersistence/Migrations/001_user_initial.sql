CREATE TABLE profiles (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  preferences_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE pokemon (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  species_id TEXT NOT NULL,
  form_id TEXT NOT NULL,
  fingerprint TEXT,
  nickname TEXT,
  cp INTEGER,
  hp INTEGER,
  level REAL,
  iv_attack INTEGER CHECK(iv_attack BETWEEN 0 AND 15),
  iv_defense INTEGER CHECK(iv_defense BETWEEN 0 AND 15),
  iv_stamina INTEGER CHECK(iv_stamina BETWEEN 0 AND 15),
  moves_json TEXT NOT NULL DEFAULT '{}',
  traits_json TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT
);
CREATE INDEX pokemon_profile_status_idx ON pokemon(profile_id, status);
CREATE INDEX pokemon_species_form_idx ON pokemon(profile_id, species_id, form_id);
CREATE INDEX pokemon_fingerprint_idx ON pokemon(profile_id, fingerprint) WHERE fingerprint IS NOT NULL;

CREATE TABLE pokemon_tags (
  pokemon_id TEXT NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  observed_at TEXT NOT NULL,
  PRIMARY KEY(pokemon_id, tag)
);

CREATE TABLE scan_sessions (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  candidate_pokemon_id TEXT REFERENCES pokemon(id),
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT
);
CREATE TABLE observations (
  id TEXT PRIMARY KEY,
  scan_session_id TEXT NOT NULL REFERENCES scan_sessions(id),
  observed_at TEXT NOT NULL,
  fields_json TEXT NOT NULL
);
CREATE INDEX observations_session_idx ON observations(scan_session_id, observed_at);

CREATE TABLE reconciliation_tasks (
  id TEXT PRIMARY KEY,
  observation_id TEXT NOT NULL REFERENCES observations(id),
  kind TEXT NOT NULL,
  candidate_ids_json TEXT NOT NULL,
  confidence REAL NOT NULL CHECK(confidence BETWEEN 0 AND 1),
  state TEXT NOT NULL,
  created_at TEXT NOT NULL,
  resolved_at TEXT
);
CREATE INDEX reconciliation_state_idx ON reconciliation_tasks(state, created_at);

CREATE TABLE collection_history (
  id TEXT PRIMARY KEY,
  pokemon_id TEXT NOT NULL REFERENCES pokemon(id),
  event_type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  payload_json TEXT
);
CREATE INDEX history_pokemon_time_idx ON collection_history(pokemon_id, occurred_at);

CREATE TABLE resources (
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  resource_id TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  observed_at TEXT NOT NULL,
  confidence REAL NOT NULL CHECK(confidence BETWEEN 0 AND 1),
  PRIMARY KEY(profile_id, resource_id)
);
CREATE TABLE storage_profiles (
  profile_id TEXT PRIMARY KEY REFERENCES profiles(id),
  pokemon_used INTEGER NOT NULL,
  pokemon_capacity INTEGER NOT NULL,
  bag_used INTEGER NOT NULL,
  bag_capacity INTEGER NOT NULL,
  observed_at TEXT NOT NULL
);
CREATE TABLE build_plans (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  pokemon_id TEXT NOT NULL REFERENCES pokemon(id),
  title TEXT NOT NULL,
  steps_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
