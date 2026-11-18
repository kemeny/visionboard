-- Optional Sign in with Apple accounts (not yet applied to production).
-- An account only backs up the list of its boards, so a new device can
-- reconnect them. The list holds sync keys, so it is stored encrypted
-- (AES-GCM, key derived from ACCOUNT_SECRET and the account id).
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,          -- Apple's stable user id ("sub" of the identity token)
  email TEXT,                   -- only when the person shared it, possibly a private relay address
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  boards_ciphertext TEXT        -- base64url(iv || AES-GCM ciphertext) of [{name, syncKey}]
);
