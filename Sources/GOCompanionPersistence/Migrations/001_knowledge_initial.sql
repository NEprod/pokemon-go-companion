CREATE TABLE provider_versions (
  provider_name TEXT NOT NULL,
  category TEXT NOT NULL,
  source_version TEXT NOT NULL,
  parser_version TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  activated_at TEXT,
  status TEXT NOT NULL,
  error TEXT,
  PRIMARY KEY(provider_name, category, source_version)
);
CREATE INDEX provider_active_idx ON provider_versions(category, activated_at);

CREATE TABLE species_forms (
  species_id TEXT NOT NULL,
  form_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  types_json TEXT NOT NULL,
  base_attack INTEGER NOT NULL,
  base_defense INTEGER NOT NULL,
  base_stamina INTEGER NOT NULL,
  mechanics_json TEXT NOT NULL,
  source_version TEXT NOT NULL,
  PRIMARY KEY(species_id, form_id, source_version)
);
CREATE TABLE moves (
  move_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  move_kind TEXT NOT NULL,
  type TEXT NOT NULL,
  pve_json TEXT,
  pvp_json TEXT,
  source_version TEXT NOT NULL,
  PRIMARY KEY(move_id, source_version)
);
CREATE TABLE move_availability_rules (
  id TEXT PRIMARY KEY,
  species_id TEXT NOT NULL,
  form_id TEXT,
  move_id TEXT NOT NULL,
  method TEXT NOT NULL,
  starts_at TEXT,
  ends_at TEXT,
  rules_json TEXT NOT NULL,
  source_version TEXT NOT NULL
);
CREATE INDEX move_rules_lookup_idx ON move_availability_rules(species_id, form_id, move_id, starts_at, ends_at);

CREATE TABLE events (
  event_id TEXT NOT NULL,
  name TEXT NOT NULL,
  starts_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  timing_mode TEXT NOT NULL,
  details_json TEXT NOT NULL,
  source_version TEXT NOT NULL,
  PRIMARY KEY(event_id, source_version)
);
CREATE TABLE event_opportunities (
  opportunity_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  opportunity_type TEXT NOT NULL,
  species_id TEXT,
  move_id TEXT,
  details_json TEXT NOT NULL,
  source_version TEXT NOT NULL,
  PRIMARY KEY(opportunity_id, source_version)
);
CREATE INDEX opportunities_time_idx ON event_opportunities(opportunity_type, species_id);

CREATE TABLE source_cache_entries (
  provider_name TEXT NOT NULL,
  category TEXT NOT NULL,
  source_version TEXT NOT NULL,
  parser_version TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  local_path TEXT NOT NULL,
  validated_at TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(provider_name, category, source_version)
);
