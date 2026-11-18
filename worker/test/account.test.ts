// Session tokens, Apple identity token checks and backup encryption.
import assert from 'node:assert/strict'
import {
  appleClientSecret,
  b64urlEncode,
  cleanBackup,
  decryptAppleToken,
  decryptBackup,
  encryptAppleToken,
  encryptBackup,
  exchangeAppleCode,
  revokeAppleToken,
  sha256HexOf,
  signSession,
  verifyAppleToken,
  verifySession,
  type AppleJWK,
} from '../src/account.ts'

const enc = new TextEncoder()
const secret = 'test-secret-that-is-long-enough-0123456789'
const now = 1_800_000_000

// Sessions round-trip, expire after 90 days and reject tampering or another secret
const token = await signSession('apple-user-1', 1234, secret, now)
assert.deepEqual(await verifySession(token, secret, now + 60), { sub: 'apple-user-1', exp: now + 90 * 86_400, ep: 1234 })
assert.equal(await verifySession(token, secret, now + 91 * 86_400), null, 'expired')
assert.equal(await verifySession(token, 'another-secret-that-is-long-enough-xyz', now), null, 'wrong secret')
const [v, payload, sig] = token.split('.')
const forged = b64urlEncode(enc.encode(JSON.stringify({ sub: 'someone-else', exp: now + 1000 })))
assert.equal(await verifySession(`${v}.${forged}.${sig}`, secret, now), null, 'forged payload')
assert.equal(await verifySession(`${v}.${payload}`, secret, now), null, 'missing signature')
assert.equal(await verifySession('garbage', secret, now), null)
// A token without the account epoch (issued before epochs existed) is refused
const noEpochBody = `v1.${b64urlEncode(enc.encode(JSON.stringify({ sub: 'apple-user-1', exp: now + 1000 })))}`
const hmac = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
const noEpochSig = new Uint8Array(await crypto.subtle.sign('HMAC', hmac, enc.encode(noEpochBody)))
assert.equal(await verifySession(`${noEpochBody}.${b64urlEncode(noEpochSig)}`, secret, now), null, 'no epoch')

// Apple identity tokens: sign one with a test RSA key standing in for Apple's
const pair = (await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true,
  ['sign', 'verify']
)) as CryptoKeyPair
const jwk = (await crypto.subtle.exportKey('jwk', pair.publicKey)) as JsonWebKey
const keys: AppleJWK[] = [{ kty: 'RSA', kid: 'test-kid', alg: 'RS256', use: 'sig', n: jwk.n!, e: jwk.e! }]
const getKeys = async () => keys

async function appleToken(claims: Record<string, unknown>, kid = 'test-kid') {
  const head = b64urlEncode(enc.encode(JSON.stringify({ alg: 'RS256', kid })))
  const body = b64urlEncode(enc.encode(JSON.stringify(claims)))
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, enc.encode(`${head}.${body}`))
  return `${head}.${body}.${b64urlEncode(new Uint8Array(signature))}`
}

const aud = 'com.kemenystudio.visionboard'
const rawNonce = 'a-random-nonce-from-the-app'
const nonce = await sha256HexOf(rawNonce)
const good = { iss: 'https://appleid.apple.com', aud, exp: now + 600, sub: '001234.abcd', email: 'x@privaterelay.appleid.com', nonce }
assert.deepEqual(await verifyAppleToken(await appleToken(good), aud, rawNonce, getKeys, now), {
  sub: '001234.abcd',
  email: 'x@privaterelay.appleid.com',
})
assert.deepEqual(await verifyAppleToken(await appleToken({ ...good, email: undefined }), aud, rawNonce, getKeys, now), {
  sub: '001234.abcd',
  email: null,
})
const rejects = async (t: string, why: RegExp, raw = rawNonce) => assert.rejects(verifyAppleToken(t, aud, raw, getKeys, now), why)
await rejects(await appleToken({ ...good, aud: 'com.example.other' }), /audience/)
await rejects(await appleToken({ ...good, iss: 'https://evil.example' }), /issuer/)
await rejects(await appleToken({ ...good, exp: now - 1 }), /expired/)
await rejects(await appleToken(good, 'other-kid'), /Unknown signing key/)
const real = await appleToken(good)
const tampered = real.split('.')
tampered[1] = b64urlEncode(enc.encode(JSON.stringify({ ...good, sub: 'attacker' })))
await rejects(tampered.join('.'), /signature/)
// A replayed token fails without the nonce it was made for
await rejects(real, /nonce/, 'some-other-nonce')
await rejects(real, /nonce/, '')
await rejects(await appleToken({ ...good, nonce: undefined }), /nonce/)

// Backups decrypt only for the same account and secret
const boards = [{ name: 'Travel', syncKey: 'abcd-efgh-ijkm-npqr-stuv' }]
const sealed = await encryptBackup(boards, secret, 'apple-user-1')
assert.ok(!sealed.includes('abcd'), 'sync key not visible in ciphertext')
assert.deepEqual(await decryptBackup(sealed, secret, 'apple-user-1'), boards)
await assert.rejects(decryptBackup(sealed, secret, 'apple-user-2'))
await assert.rejects(decryptBackup(sealed, 'another-secret-that-is-long-enough-xyz', 'apple-user-1'))

assert.deepEqual(cleanBackup(boards), boards)
assert.equal(cleanBackup([{ name: 'x', syncKey: 'short' }]), null)
assert.equal(cleanBackup('nope'), null)

// Apple refresh tokens are sealed per account, apart from the backup key
const appleSealed = await encryptAppleToken('r.apple-refresh', secret, 'apple-user-1')
assert.equal(await decryptAppleToken(appleSealed, secret, 'apple-user-1'), 'r.apple-refresh')
await assert.rejects(decryptAppleToken(appleSealed, secret, 'apple-user-2'))
await assert.rejects(decryptBackup(appleSealed, secret, 'apple-user-1'))

// The client secret is an ES256 JWT that verifies with the key's public half
const ecPair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'])) as CryptoKeyPair
const pkcs8 = new Uint8Array((await crypto.subtle.exportKey('pkcs8', ecPair.privateKey)) as ArrayBuffer)
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`
const config = { teamId: 'TEAM123456', keyId: 'KEY1234567', privateKey: pem, clientId: aud }
const clientSecret = await appleClientSecret(config, now)
const [h, c, sgn] = clientSecret.split('.')
const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/')))
assert.deepEqual(decode(h), { alg: 'ES256', kid: 'KEY1234567', typ: 'JWT' })
assert.deepEqual(decode(c), { iss: 'TEAM123456', iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: aud })
const sigBytes = Uint8Array.from(atob(sgn.replace(/-/g, '+').replace(/_/g, '/')), (ch) => ch.charCodeAt(0))
assert.ok(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, ecPair.publicKey, sigBytes, enc.encode(`${h}.${c}`)))
// A .p8 pasted with literal "\n" escapes still loads
assert.ok(await appleClientSecret({ ...config, privateKey: pem.replace(/\n/g, '\\n') }, now))

// Code exchange and revoke talk to Apple's endpoints with the right form
const calls: { url: string; body: URLSearchParams }[] = []
const fakeApple = (status: number, body: unknown) =>
  (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), body: new URLSearchParams(String(init?.body)) })
    return new Response(JSON.stringify(body), { status })
  }) as typeof fetch
assert.equal(await exchangeAppleCode('code-1', config, fakeApple(200, { refresh_token: 'r.1' })), 'r.1')
assert.equal(calls[0].url, 'https://appleid.apple.com/auth/token')
assert.equal(calls[0].body.get('grant_type'), 'authorization_code')
assert.equal(calls[0].body.get('code'), 'code-1')
assert.equal(await exchangeAppleCode('used', config, fakeApple(400, { error: 'invalid_grant' })), null)
assert.equal(await revokeAppleToken('r.1', config, fakeApple(200, {})), true)
assert.equal(calls[2].url, 'https://appleid.apple.com/auth/revoke')
assert.equal(calls[2].body.get('token_type_hint'), 'refresh_token')
assert.equal(calls[2].body.get('token'), 'r.1')
assert.equal(await revokeAppleToken('gone', config, fakeApple(400, { error: 'invalid_request' })), true)
assert.equal(await revokeAppleToken('r.1', config, fakeApple(503, {})), false)

console.log('account: ok')
