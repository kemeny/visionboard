// Round-trip check: encrypt like a push server receives it, then decrypt
// like a browser would (RFC 8291), and verify the VAPID-style signature.
import assert from 'node:assert/strict'
import { b64urlDecode, b64urlEncode, encryptPayload, generateVapidKeys } from '../src/webpush.ts'

const enc = new TextEncoder()
const concat = (...p: Uint8Array[]) => {
  const o = new Uint8Array(p.reduce((n, x) => n + x.length, 0))
  let i = 0
  for (const x of p) { o.set(x, i); i += x.length }
  return o
}
const hmac = async (k: Uint8Array, d: Uint8Array) =>
  new Uint8Array(await crypto.subtle.sign('HMAC', await crypto.subtle.importKey('raw', k, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']), d))

// Browser side
const ua = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits'])
const uaPublic = new Uint8Array(await crypto.subtle.exportKey('raw', ua.publicKey))
const auth = crypto.getRandomValues(new Uint8Array(16))
const sub = { endpoint: 'https://push.example/x', keys: { p256dh: b64urlEncode(uaPublic), auth: b64urlEncode(auth) } }

const message = JSON.stringify({ title: 'Your vision board', body: 'Run a marathon 🏃' })
const body = await encryptPayload(sub, enc.encode(message))

const salt = body.slice(0, 16)
assert.equal(new DataView(body.buffer).getUint32(16), 4096)
const idlen = body[20]
assert.equal(idlen, 65)
const asPublic = body.slice(21, 21 + idlen)
const ciphertext = body.slice(21 + idlen)

const asKey = await crypto.subtle.importKey('raw', asPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, [])
const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: asKey }, ua.privateKey, 256))
const ikm = await hmac(await hmac(auth, ecdh), concat(enc.encode('WebPush: info\0'), uaPublic, asPublic, new Uint8Array([1])))
const prk = await hmac(salt, ikm)
const cek = (await hmac(prk, enc.encode('Content-Encoding: aes128gcm\0\x01'))).slice(0, 16)
const nonce = (await hmac(prk, enc.encode('Content-Encoding: nonce\0\x01'))).slice(0, 12)
const plain = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce },
  await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['decrypt']), ciphertext))
assert.equal(plain[plain.length - 1], 2, 'last-record delimiter')
assert.equal(new TextDecoder().decode(plain.slice(0, -1)), message)

// VAPID keys sign and verify
const vapid = await generateVapidKeys()
assert.equal(b64urlDecode(vapid.publicKey).length, 65)
const priv = await crypto.subtle.importKey('jwk', vapid.privateJwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'])
const pub = await crypto.subtle.importKey('raw', b64urlDecode(vapid.publicKey), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify'])
const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, priv, enc.encode('x'))
assert.ok(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pub, sig, enc.encode('x')))

console.log('webpush: ok')
