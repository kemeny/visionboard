// StoreKit signed transactions: chain, root pin, signature and plan checks.
// Uses a throwaway openssl chain (fixtures/storekit-chain.json) pinned in
// place of Apple's root.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { isActivePro, verifySignedTransaction } from '../src/storekit.ts'

const fixture = JSON.parse(readFileSync(new URL('./fixtures/storekit-chain.json', import.meta.url), 'utf8')) as {
  x5c: string[]
  leafKeyPkcs8: string
}
const enc = new TextEncoder()
const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const fromB64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0))

const rootDer = fromB64(fixture.x5c[2])
const root = [...new Uint8Array(await crypto.subtle.digest('SHA-256', rootDer))]
  .map((b) => b.toString(16).padStart(2, '0'))
  .join('')
const leafKey = await crypto.subtle.importKey('pkcs8', fromB64(fixture.leafKeyPkcs8), { name: 'ECDSA', namedCurve: 'P-256' }, false, [
  'sign',
])

const now = Date.UTC(2027, 0, 15)
const bundle = 'com.kemenystudio.visionboard'
const active = {
  bundleId: bundle,
  productId: 'com.kemenystudio.visionboard.pro.yearly',
  originalTransactionId: '2000000123',
  expiresDate: now + 7 * 86_400_000,
}

async function sign(payload: unknown, x5c = fixture.x5c) {
  const head = b64url(enc.encode(JSON.stringify({ alg: 'ES256', x5c })))
  const body = b64url(enc.encode(JSON.stringify(payload)))
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, leafKey, enc.encode(`${head}.${body}`)))
  return `${head}.${body}.${b64url(sig)}`
}

// A good transaction verifies through the whole chain
const good = await sign(active)
assert.equal((await verifySignedTransaction(good, now, root)).productId, active.productId)
assert.equal(await isActivePro(good, bundle, now, root), true)

// Apple's real root is pinned by default, so a self-made chain never passes
assert.equal(await isActivePro(good, bundle, now), false)

// Plan checks
assert.equal(await isActivePro(await sign({ ...active, expiresDate: now - 1 }), bundle, now, root), false, 'expired')
assert.equal(await isActivePro(await sign({ ...active, revocationDate: now - 1 }), bundle, now, root), false, 'refunded')
assert.equal(await isActivePro(await sign({ ...active, productId: 'com.example.other' }), bundle, now, root), false, 'product')
assert.equal(await isActivePro(await sign({ ...active, bundleId: 'com.example.app' }), bundle, now, root), false, 'bundle')
assert.equal(await isActivePro(await sign({ ...active, expiresDate: undefined }), bundle, now, root), false, 'no expiry')

// Tampering and broken chains
const parts = good.split('.')
const forged = `${parts[0]}.${b64url(enc.encode(JSON.stringify({ ...active, expiresDate: now + 1e12 })))}.${parts[2]}`
await assert.rejects(verifySignedTransaction(forged, now, root), /signature/)
await assert.rejects(verifySignedTransaction(await sign(active, [fixture.x5c[0], fixture.x5c[2]]), now, root), /chain/)
await assert.rejects(verifySignedTransaction(await sign(active, [fixture.x5c[1], fixture.x5c[2]]), now, root), /signature|key/)
await assert.rejects(verifySignedTransaction(good, Date.UTC(2020, 0, 1), root), /not valid/)
assert.equal(await isActivePro('a.b.c', bundle, now, root), false)
assert.equal(await isActivePro('', bundle, now, root), false)

console.log('storekit ok')
