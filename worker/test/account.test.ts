// Session tokens, Apple identity token checks and backup encryption.
import assert from 'node:assert/strict'
import {
  b64urlEncode,
  cleanBackup,
  decryptBackup,
  encryptBackup,
  signSession,
  verifyAppleToken,
  verifySession,
  type AppleJWK,
} from '../src/account.ts'

const enc = new TextEncoder()
const secret = 'test-secret-that-is-long-enough-0123456789'
const now = 1_800_000_000

// Sessions round-trip, expire after 90 days and reject tampering or another secret
const token = await signSession('apple-user-1', secret, now)
assert.deepEqual(await verifySession(token, secret, now + 60), { sub: 'apple-user-1', exp: now + 90 * 86_400 })
assert.equal(await verifySession(token, secret, now + 91 * 86_400), null, 'expired')
assert.equal(await verifySession(token, 'another-secret-that-is-long-enough-xyz', now), null, 'wrong secret')
const [v, payload, sig] = token.split('.')
const forged = b64urlEncode(enc.encode(JSON.stringify({ sub: 'someone-else', exp: now + 1000 })))
assert.equal(await verifySession(`${v}.${forged}.${sig}`, secret, now), null, 'forged payload')
assert.equal(await verifySession(`${v}.${payload}`, secret, now), null, 'missing signature')
assert.equal(await verifySession('garbage', secret, now), null)

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
const good = { iss: 'https://appleid.apple.com', aud, exp: now + 600, sub: '001234.abcd', email: 'x@privaterelay.appleid.com' }
assert.deepEqual(await verifyAppleToken(await appleToken(good), aud, getKeys, now), {
  sub: '001234.abcd',
  email: 'x@privaterelay.appleid.com',
})
assert.deepEqual(await verifyAppleToken(await appleToken({ ...good, email: undefined }), aud, getKeys, now), {
  sub: '001234.abcd',
  email: null,
})
const rejects = async (t: string, why: RegExp) => assert.rejects(verifyAppleToken(t, aud, getKeys, now), why)
await rejects(await appleToken({ ...good, aud: 'com.example.other' }), /audience/)
await rejects(await appleToken({ ...good, iss: 'https://evil.example' }), /issuer/)
await rejects(await appleToken({ ...good, exp: now - 1 }), /expired/)
await rejects(await appleToken(good, 'other-kid'), /Unknown signing key/)
const real = await appleToken(good)
const tampered = real.split('.')
tampered[1] = b64urlEncode(enc.encode(JSON.stringify({ ...good, sub: 'attacker' })))
await rejects(tampered.join('.'), /signature/)

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

console.log('account: ok')
