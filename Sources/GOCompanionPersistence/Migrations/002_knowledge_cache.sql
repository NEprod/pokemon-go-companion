CREATE TABLE source_payloads (
  provider_name TEXT NOT NULL,
  category TEXT NOT NULL,
  source_version TEXT NOT NULL,
  parser_version TEXT NOT NULL,
  etag TEXT,
  checksum TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  payload BLOB NOT NULL,
  validation_status TEXT NOT NULL CHECK(validation_status IN ('valid', 'invalid')),
  validation_error TEXT,
  lifecycle_state TEXT NOT NULL DEFAULT 'candidate'
    CHECK(lifecycle_state IN ('candidate', 'active', 'previous', 'inactive', 'invalid')),
  activated_at TEXT,
  PRIMARY KEY(provider_name, category, source_version, parser_version)
);
CREATE INDEX source_payload_state_idx ON source_payloads(category, lifecycle_state, fetched_at);

CREATE TABLE knowledge_datasets (
  normalized_version TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  provider_name TEXT NOT NULL,
  source_version TEXT NOT NULL,
  parser_version TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  payload_json BLOB NOT NULL,
  lifecycle_state TEXT NOT NULL CHECK(lifecycle_state IN ('staged', 'active', 'previous', 'inactive')),
  staged_at TEXT NOT NULL,
  activated_at TEXT,
  UNIQUE(category, provider_name, source_version, parser_version)
);
CREATE INDEX knowledge_dataset_state_idx ON knowledge_datasets(category, lifecycle_state);

CREATE TABLE knowledge_active_versions (
  category TEXT PRIMARY KEY,
  active_normalized_version TEXT NOT NULL REFERENCES knowledge_datasets(normalized_version),
  previous_normalized_version TEXT REFERENCES knowledge_datasets(normalized_version),
  updated_at TEXT NOT NULL
);

CREATE TABLE knowledge_types (
  normalized_version TEXT NOT NULL REFERENCES knowledge_datasets(normalized_version) ON DELETE CASCADE,
  type_id TEXT NOT NULL,
  PRIMARY KEY(normalized_version, type_id)
);

CREATE TABLE knowledge_species_forms (
  normalized_version TEXT NOT NULL REFERENCES knowledge_datasets(normalized_version) ON DELETE CASCADE,
  species_id TEXT NOT NULL,
  form_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  primary_type_id TEXT NOT NULL,
  secondary_type_id TEXT,
  base_attack INTEGER NOT NULL CHECK(base_attack > 0),
  base_defense INTEGER NOT NULL CHECK(base_defense > 0),
  base_stamina INTEGER NOT NULL CHECK(base_stamina > 0),
  evolution_family_id TEXT NOT NULL,
  shadow_capable INTEGER NOT NULL CHECK(shadow_capable IN (0, 1)),
  mega_capable INTEGER NOT NULL CHECK(mega_capable IN (0, 1)),
  dynamax_capable INTEGER NOT NULL CHECK(dynamax_capable IN (0, 1)),
  gigantamax_capable INTEGER NOT NULL CHECK(gigantamax_capable IN (0, 1)),
  PRIMARY KEY(normalized_version, species_id, form_id),
  FOREIGN KEY(normalized_version, primary_type_id)
    REFERENCES knowledge_types(normalized_version, type_id),
  FOREIGN KEY(normalized_version, secondary_type_id)
    REFERENCES knowledge_types(normalized_version, type_id)
);

CREATE TABLE knowledge_evolutions (
  normalized_version TEXT NOT NULL REFERENCES knowledge_datasets(normalized_version) ON DELETE CASCADE,
  from_species_id TEXT NOT NULL,
  from_form_id TEXT NOT NULL,
  to_species_id TEXT NOT NULL,
  to_form_id TEXT NOT NULL,
  candy_cost INTEGER NOT NULL CHECK(candy_cost >= 0),
  requirements_json TEXT NOT NULL,
  PRIMARY KEY(normalized_version, from_species_id, from_form_id, to_species_id, to_form_id),
  FOREIGN KEY(normalized_version, from_species_id, from_form_id)
    REFERENCES knowledge_species_forms(normalized_version, species_id, form_id),
  FOREIGN KEY(normalized_version, to_species_id, to_form_id)
    REFERENCES knowledge_species_forms(normalized_version, species_id, form_id)
);

CREATE TABLE knowledge_moves (
  normalized_version TEXT NOT NULL REFERENCES knowledge_datasets(normalized_version) ON DELETE CASCADE,
  move_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  move_kind TEXT NOT NULL CHECK(move_kind IN ('fast', 'charged')),
  type_id TEXT NOT NULL,
  pve_json TEXT NOT NULL,
  pvp_json TEXT NOT NULL,
  PRIMARY KEY(normalized_version, move_id),
  FOREIGN KEY(normalized_version, type_id)
    REFERENCES knowledge_types(normalized_version, type_id)
);

CREATE TABLE knowledge_move_pools (
  normalized_version TEXT NOT NULL REFERENCES knowledge_datasets(normalized_version) ON DELETE CASCADE,
  species_id TEXT NOT NULL,
  form_id TEXT NOT NULL,
  move_id TEXT NOT NULL,
  availability TEXT NOT NULL,
  PRIMARY KEY(normalized_version, species_id, form_id, move_id, availability),
  FOREIGN KEY(normalized_version, species_id, form_id)
    REFERENCES knowledge_species_forms(normalized_version, species_id, form_id),
  FOREIGN KEY(normalized_version, move_id)
    REFERENCES knowledge_moves(normalized_version, move_id)
);

CREATE TABLE knowledge_cp_multipliers (
  normalized_version TEXT NOT NULL REFERENCES knowledge_datasets(normalized_version) ON DELETE CASCADE,
  level_half_steps INTEGER NOT NULL CHECK(level_half_steps >= 2),
  multiplier REAL NOT NULL CHECK(multiplier > 0 AND multiplier <= 1),
  stardust_cost INTEGER NOT NULL CHECK(stardust_cost >= 0),
  candy_cost INTEGER NOT NULL CHECK(candy_cost >= 0),
  xl_candy_cost INTEGER NOT NULL CHECK(xl_candy_cost >= 0),
  requires_xl INTEGER NOT NULL CHECK(requires_xl IN (0, 1)),
  best_buddy_only INTEGER NOT NULL CHECK(best_buddy_only IN (0, 1)),
  PRIMARY KEY(normalized_version, level_half_steps)
);
