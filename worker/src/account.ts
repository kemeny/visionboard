// Optional Sign in with Apple accounts. An account only backs up the list of
// a person's boards (name and sync key), so a new iPhone can reconnect them.
// Boards themselves stay keyed by their sync key, exactly as before.
//
// Everything here uses WebCrypto only, so it runs in the Worker and in Node
// (worker/test/account.test.ts).

export const APPLE_ISSUER = 'https://appleid.apple.com'
export const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys'
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
// "v1.<payload>.<signature>": the payload is {sub, exp} as base64url JSON and
// the signature is HMAC-SHA256 over "v1.<payload>" with ACCOUNT_SECRET.

export interface Session {
  sub: string
  exp: number // seconds since 1970
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
}

export async function signSession(sub: string, secret: string, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const payload: Session = { sub, exp: nowSeconds + SESSION_DAYS * 86_400 }
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
// refetches early only when a token names a key it doesn't know.
let cachedKeys: { keys: AppleJWK[]; at: number } | null = null
const KEY_TTL_MS = 60 * 60 * 1000

export const fetchAppleKeys: KeyFetcher = async (refresh) => {
  if (!refresh && cachedKeys && Date.now() - cachedKeys.at < KEY_TTL_MS) return cachedKeys.keys
  const response = await fetch(APPLE_KEYS_URL)
  if (!response.ok) throw new Error(`Apple keys request failed (${response.status})`)
  const { keys } = (await response.json()) as { keys: AppleJWK[] }
  cachedKeys = { keys, at: Date.now() }
  return keys
}

export class TokenError extends Error {}

// Checks the signature (RS256 with one of Apple's keys), issuer, audience
// (the app's bundle id) and expiry. Returns the stable user id and email.
export async function verifyAppleToken(
  token: string,
  audience: string,
  getKeys: KeyFetcher = fetchAppleKeys,
  nowSeconds = Math.floor(Date.now() / 1000)
): Promise<AppleIdentity> {
  const parts = token.split('.')
  if (parts.length !== 3) throw new TokenError('Malformed token')
  let header: { alg?: string; kid?: string }
  let claims: { iss?: string; aud?: string | string[]; exp?: number; sub?: string; email?: string }
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

async function backupKey(secret: string, accountId: string): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey('raw', enc.encode(secret), 'HKDF', false, ['deriveKey'])
  return crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: enc.encode('visionboard-backup-v1'), info: enc.encode(accountId) },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  )
}

export async function encryptBackup(boards: BackupBoard[], secret: string, accountId: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv, additionalData: enc.encode(accountId) },
      await backupKey(secret, accountId),
      enc.encode(JSON.stringify(boards))
    )
  )
  const out = new Uint8Array(iv.length + sealed.length)
  out.set(iv)
  out.set(sealed, iv.length)
  return b64urlEncode(out)
}

export async function decryptBackup(ciphertext: string, secret: string, accountId: string): Promise<BackupBoard[]> {
  const bytes = b64urlDecode(ciphertext)
  const plain = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: bytes.slice(0, 12), additionalData: enc.encode(accountId) },
    await backupKey(secret, accountId),
    bytes.slice(12)
  )
  return JSON.parse(dec.decode(plain)) as BackupBoard[]
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
