-- Sign in with Apple token revocation (not yet applied to production).
-- Deleting an account must revoke the app's Apple tokens (App Review
-- guideline 5.1.1(v)), so sign-in keeps Apple's refresh token, sealed with
-- AES-GCM under a key derived from ACCOUNT_SECRET and the account id, the
-- same way as the backup. NULL when it couldn't be fetched.
ALTER TABLE accounts ADD COLUMN apple_refresh_ciphertext TEXT;
