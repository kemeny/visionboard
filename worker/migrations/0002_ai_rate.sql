-- Hourly counters for the AI board routes (worker/src/ai.ts). Keys hold a
-- SHA-256 of the caller's address, never the address itself; the hourly cron
-- deletes rows once their hour is over.
CREATE TABLE IF NOT EXISTS ai_rate (
  key TEXT PRIMARY KEY,        -- "<kind>:ip:<hash>:<hour>" or "<kind>:all:<hour>"
  count INTEGER NOT NULL,
  expires_at INTEGER NOT NULL  -- ms since epoch
);
CREATE INDEX IF NOT EXISTS idx_ai_rate_expires ON ai_rate(expires_at);
