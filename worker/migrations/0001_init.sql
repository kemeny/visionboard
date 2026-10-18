-- Already applied to the production D1 database on 2026-10-17
CREATE TABLE IF NOT EXISTS boards (
  id TEXT PRIMARY KEY,          -- SHA-256 of the sync key; the key itself is never stored
  data TEXT NOT NULL,           -- board JSON, images replaced by R2 URLs
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS push_subscriptions (
  endpoint TEXT PRIMARY KEY,
  board_id TEXT NOT NULL,
  subscription TEXT NOT NULL,
  timezone TEXT NOT NULL,
  local_hour INTEGER NOT NULL,
  last_sent_day TEXT,
  created_at INTEGER NOT NULL,
  app_origin TEXT              -- where the notification click should open
);
CREATE INDEX IF NOT EXISTS idx_push_board ON push_subscriptions(board_id);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
