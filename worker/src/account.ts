// Optional Sign in with Apple accounts. An account only backs up the list of
// a person's boards (name and sync key), so a new iPhone can reconnect them.
// Boards themselves stay keyed by their sync key, exactly as before.
//
// Everything here uses WebCrypto only, so it runs in the Worker and in Node
// (worker/test/account.test.ts).

export const APPLE_ISSUER = 'https://appleid.apple.com'
export const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys'
export const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token'
export const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke'
export const DEFAULT_BUNDLE_ID = 'com.kemenystudio.visionboard'
export const SESSION_DAYS = 90

const enc = new TextEncoder()
const dec = new TextDecoder()

export function b64urlEncode(bytes: Uint8Array): string {
  let s = ''
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function b64urlDecode(text: string): Uint8Array {
  const padded = text.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((text.length + 3) % 4)
  const raw = atob(padded)
  const out = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}

function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}

// MARK: Session tokens
//
// "v1.<payload>.<signature>": the payload is {sub, exp, ep} as base64url JSON
// and the signature is HMAC-SHA256 over "v1.<payload>" with ACCOUNT_SECRET.
// `ep` is the account's created_at: deleting the account and signing in again
// makes a new row with a new created_at, so every older token stops working.

export interface Session {
  sub: string
  exp: number // seconds since 1970
  ep: number // the account row's created_at when the token was issued
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
}

export async function signSession(
  sub: string,
  epoch: number,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000)
): Promise<string> {
  const payload: Session = { sub, exp: nowSeconds + SESSION_DAYS * 86_400, ep: epoch }
  const body = `v1.${b64urlEncode(enc.encode(JSON.stringify(payload)))}`
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', await hmacKey(secret), enc.encode(body)))
  return `${body}.${b64urlEncode(sig)}`
}

export async function verifySession(
  token: string,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000)
): Promise<Session | null> {
  const parts = token.split('.')
  if (parts.length !== 3 || parts[0] !== 'v1') return null
  try {
    const body = `${parts[0]}.${parts[1]}`
    const expected = new Uint8Array(await crypto.subtle.sign('HMAC', await hmacKey(secret), enc.encode(body)))
    if (!timingSafeEqual(expected, b64urlDecode(parts[2]))) return null
    const session = JSON.parse(dec.decode(b64urlDecode(parts[1]))) as Session
    if (typeof session.sub !== 'string' || !session.sub || typeof session.exp !== 'number') return null
    if (typeof session.ep !== 'number') return null
    if (session.exp <= nowSeconds) return null
    return session
  } catch {
    return null
  }
}

// MARK: Apple identity tokens

export interface AppleJWK {
  kty: string
  kid: string
  use?: string
  alg?: string
  n: string
  e: string
}

export interface AppleIdentity {
  sub: string
  email: string | null
}

export type KeyFetcher = (refresh: boolean) => Promise<AppleJWK[]>

// Apple rotates its keys rarely, so an isolate keeps them for an hour and
// refetches early only when a token names a key it doesn't know. An early
// refetch happens at most once a minute, so tokens with made-up key ids
// can't make every request call Apple.
let cachedKeys: { keys: AppleJWK[]; at: number } | null = null
let lastForcedRefresh = 0
const KEY_TTL_MS = 60 * 60 * 1000
const FORCED_REFRESH_MS = 60 * 1000

export const fetchAppleKeys: KeyFetcher = async (refresh) => {
  const now = Date.now()
  const fresh = cachedKeys && now - cachedKeys.at < KEY_TTL_MS
  if (cachedKeys && (refresh ? now - lastForcedRefresh < FORCED_REFRESH_MS : fresh)) return cachedKeys.keys
  if (refresh) lastForcedRefresh = now
  const response = await fetch(APPLE_KEYS_URL)
  if (!response.ok) throw new Error(`Apple keys request failed (${response.status})`)
  const { keys } = (await response.json()) as { keys: AppleJWK[] }
  cachedKeys = { keys, at: Date.now() }
  return keys
}

export class TokenError extends Error {}

export async function sha256HexOf(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(text))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

// Checks the signature (RS256 with one of Apple's keys), issuer, audience
// (the app's bundle id), expiry and nonce. The app puts SHA-256(rawNonce) in
// the request and sends rawNonce here, so a token copied from elsewhere can't
// be replayed. Returns the stable user id and email.
export async function verifyAppleToken(
  token: string,
  audience: string,
  rawNonce: string,
  getKeys: KeyFetcher = fetchAppleKeys,
  nowSeconds = Math.floor(Date.now() / 1000)
): Promise<AppleIdentity> {
  const parts = token.split('.')
  if (parts.length !== 3) throw new TokenError('Malformed token')
  let header: { alg?: string; kid?: string }
  let claims: { iss?: string; aud?: string | string[]; exp?: number; sub?: string; email?: string; nonce?: string }
  try {
    header = JSON.parse(dec.decode(b64urlDecode(parts[0])))
    claims = JSON.parse(dec.decode(b64urlDecode(parts[1])))
  } catch {
    throw new TokenError('Malformed token')
  }
  if (header.alg !== 'RS256' || !header.kid) throw new TokenError('Unsupported token')

  let jwk = (await getKeys(false)).find((k) => k.kid === header.kid)
  if (!jwk) jwk = (await getKeys(true)).find((k) => k.kid === header.kid)
  if (!jwk) throw new TokenError('Unknown signing key')

  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  )
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlDecode(parts[2]),
    enc.encode(`${parts[0]}.${parts[1]}`)
  )
  if (!valid) throw new TokenError('Bad signature')

  if (claims.iss !== APPLE_ISSUER) throw new TokenError('Wrong issuer')
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud]
  if (!audiences.includes(audience)) throw new TokenError('Wrong audience')
  if (typeof claims.exp !== 'number' || claims.exp <= nowSeconds) throw new TokenError('Token expired')
  if (typeof claims.sub !== 'string' || !claims.sub) throw new TokenError('Token has no subject')
  if (!rawNonce || typeof claims.nonce !== 'string' || claims.nonce !== (await sha256HexOf(rawNonce))) {
    throw new TokenError('Wrong nonce')
  }

  return { sub: claims.sub, email: typeof claims.email === 'string' && claims.email ? claims.email : null }
}

// MARK: Backup encryption
//
// Each account gets its own AES-256-GCM key, derived with HKDF from
// ACCOUNT_SECRET and the account id, so the database alone never reveals a
// sync key. Stored as base64url(iv || ciphertext).

export interface BackupBoard {
  name: string
  syncKey: string
}

async function backupKey(secret: string, accountId: string, salt = 'visionboard-backup-v1'): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey('raw', enc.encode(secret), 'HKDF', false, ['deriveKey'])
  return crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: enc.encode(salt), info: enc.encode(accountId) },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  )
}

async function seal(text: string, secret: string, accountId: string, salt: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv, additionalData: enc.encode(accountId) },
      await backupKey(secret, accountId, salt),
      enc.encode(text)
    )
  )
  const out = new Uint8Array(iv.length + sealed.length)
  out.set(iv)
  out.set(sealed, iv.length)
  return b64urlEncode(out)
}

async function unseal(ciphertext: string, secret: string, accountId: string, salt: string): Promise<string> {
  const bytes = b64urlDecode(ciphertext)
  const plain = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: bytes.slice(0, 12), additionalData: enc.encode(accountId) },
    await backupKey(secret, accountId, salt),
    bytes.slice(12)
  )
  return dec.decode(plain)
}

export async function encryptBackup(boards: BackupBoard[], secret: string, accountId: string): Promise<string> {
  return seal(JSON.stringify(boards), secret, accountId, 'visionboard-backup-v1')
}

export async function decryptBackup(ciphertext: string, secret: string, accountId: string): Promise<BackupBoard[]> {
  return JSON.parse(await unseal(ciphertext, secret, accountId, 'visionboard-backup-v1')) as BackupBoard[]
}

// Apple's refresh token for the account, kept only so it can be revoked when
// the account is deleted. Sealed the same way as the backup, under its own key.
export async function encryptAppleToken(token: string, secret: string, accountId: string): Promise<string> {
  return seal(token, secret, accountId, 'visionboard-apple-token-v1')
}

export async function decryptAppleToken(ciphertext: string, secret: string, accountId: string): Promise<string> {
  return unseal(ciphertext, secret, accountId, 'visionboard-apple-token-v1')
}

// MARK: Sign in with Apple REST API
//
// Deleting an account must revoke the app's Apple tokens (App Review
// guideline 5.1.1(v)). Sign-in sends the one-time authorization code, which
// is exchanged here for a refresh token; account deletion revokes it.
// Needs a Sign in with Apple key from the developer account, set as secrets:
//   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8 file's text)

export interface AppleClientConfig {
  teamId: string
  keyId: string
  privateKey: string // PKCS#8 PEM, as in the .p8 file
  clientId: string // the app's bundle id
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\\n/g, '')
    .replace(/\s+/g, '')
  return b64urlDecode(body.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''))
}

// The client_secret Apple asks for: an ES256 JWT signed with the .p8 key
export async function appleClientSecret(config: AppleClientConfig, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = { alg: 'ES256', kid: config.keyId, typ: 'JWT' }
  const claims = { iss: config.teamId, iat: nowSeconds, exp: nowSeconds + 300, aud: APPLE_ISSUER, sub: config.clientId }
  const input = `${b64urlEncode(enc.encode(JSON.stringify(header)))}.${b64urlEncode(enc.encode(JSON.stringify(claims)))}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(config.privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )
  // WebCrypto returns r || s, which is exactly what JWS wants
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(input)))
  return `${input}.${b64urlEncode(signature)}`
}

// Trades the authorization code from sign-in for a refresh token. Null when
// Apple says no (a used or expired code).
export async function exchangeAppleCode(code: string, config: AppleClientConfig, fetcher: typeof fetch = fetch): Promise<string | null> {
  const response = await fetcher(APPLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: await appleClientSecret(config),
      code,
      grant_type: 'authorization_code',
    }),
  })
  if (!response.ok) {
    console.error('apple token exchange', response.status)
    return null
  }
  const data = (await response.json()) as { refresh_token?: unknown }
  return typeof data.refresh_token === 'string' && data.refresh_token ? data.refresh_token : null
}

// Revokes the refresh token, which signs the app out of this Apple Account
// (it leaves iOS Settings > Apple Account > Sign in with Apple). Returns
// false only when Apple couldn't be reached or failed on its side, so the
// caller can ask the person to try again; a token Apple no longer knows
// counts as revoked.
export async function revokeAppleToken(refreshToken: string, config: AppleClientConfig, fetcher: typeof fetch = fetch): Promise<boolean> {
  try {
    const response = await fetcher(APPLE_REVOKE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: await appleClientSecret(config),
        token: refreshToken,
        token_type_hint: 'refresh_token',
      }),
    })
    if (response.status >= 500) {
      console.error('apple revoke', response.status)
      return false
    }
    if (!response.ok) console.error('apple revoke refused', response.status)
    return true
  } catch (e) {
    console.error('apple revoke failed', e)
    return false
  }
}

const MAX_BACKUP_BOARDS = 200

// Keeps only well-formed entries: a short name and a key long enough to be a sync key
export function cleanBackup(input: unknown): BackupBoard[] | null {
  if (!Array.isArray(input) || input.length > MAX_BACKUP_BOARDS) return null
  const out: BackupBoard[] = []
  for (const entry of input) {
    if (!entry || typeof entry !== 'object') return null
    const { name, syncKey } = entry as { name?: unknown; syncKey?: unknown }
    if (typeof name !== 'string' || typeof syncKey !== 'string') return null
    if (syncKey.length < 20 || syncKey.length > 200) return null
    out.push({ name: name.slice(0, 100), syncKey })
  }
  return out
}
