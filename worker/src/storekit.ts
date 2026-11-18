// Checks a StoreKit 2 signed transaction (the JWS the iOS app reads from
// Transaction.currentEntitlements) so the Worker can enforce Pro itself.
//
// The JWS header carries the certificate chain in x5c: the signing
// certificate, Apple's intermediate and Apple Root CA - G3. Each certificate
// must be signed by the next and be valid now, the last one must be Apple's
// root (by SHA-256 fingerprint), and the leaf's key must have signed the JWS.
// WebCrypto only, with a small DER reader, so it runs in the Worker and in
// Node (worker/test/storekit.test.ts).

// SHA-256 of Apple Root CA - G3 (https://www.apple.com/certificateauthority/)
export const APPLE_ROOT_CA_G3_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179'

export const PRO_PRODUCT_IDS = new Set([
  'com.kemenystudio.visionboard.pro.yearly',
  'com.kemenystudio.visionboard.pro.monthly',
])

export class ProofError extends Error {}

const enc = new TextEncoder()
const dec = new TextDecoder()

function b64ToBytes(text: string): Uint8Array {
  const normal = text.replace(/-/g, '+').replace(/_/g, '/').replace(/\s+/g, '')
  const raw = atob(normal + '==='.slice((normal.length + 3) % 4))
  const out = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

// MARK: DER

interface Node {
  tag: number
  start: number // first byte of the tag
  contentStart: number
  end: number // one past the last content byte
}

function readNode(bytes: Uint8Array, offset: number): Node {
  if (offset + 2 > bytes.length) throw new ProofError('Bad certificate')
  const tag = bytes[offset]
  let length = bytes[offset + 1]
  let cursor = offset + 2
  if (length & 0x80) {
    const count = length & 0x7f
    if (count === 0 || count > 4 || cursor + count > bytes.length) throw new ProofError('Bad certificate')
    length = 0
    for (let i = 0; i < count; i++) length = length * 256 + bytes[cursor + i]
    cursor += count
  }
  const end = cursor + length
  if (end > bytes.length) throw new ProofError('Bad certificate')
  return { tag, start: offset, contentStart: cursor, end }
}

function children(bytes: Uint8Array, node: Node): Node[] {
  const out: Node[] = []
  let offset = node.contentStart
  while (offset < node.end) {
    const child = readNode(bytes, offset)
    out.push(child)
    offset = child.end
  }
  return out
}

const OID_ECDSA_SHA256 = '2a8648ce3d040302'
const OID_ECDSA_SHA384 = '2a8648ce3d040303'
const OID_P256 = '2a8648ce3d030107'
const OID_P384 = '2b81040022'

interface Certificate {
  der: Uint8Array
  tbs: Uint8Array
  signatureAlg: string // OID bytes as hex
  signature: Uint8Array // DER ECDSA signature
  issuer: Uint8Array
  subject: Uint8Array
  notBefore: number
  notAfter: number
  spki: Uint8Array
  curve: 'P-256' | 'P-384'
}

function parseTime(bytes: Uint8Array, node: Node): number {
  const text = dec.decode(bytes.slice(node.contentStart, node.end))
  let match: RegExpMatchArray | null
  if (node.tag === 0x17) {
    match = text.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/)
    if (!match) throw new ProofError('Bad certificate time')
    const year = Number(match[1]) + (Number(match[1]) < 50 ? 2000 : 1900)
    return Date.UTC(year, Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6]))
  }
  if (node.tag === 0x18) {
    match = text.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/)
    if (!match) throw new ProofError('Bad certificate time')
    return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6]))
  }
  throw new ProofError('Bad certificate time')
}

function parseCertificate(der: Uint8Array): Certificate {
  const root = readNode(der, 0)
  const [tbsNode, algNode, sigNode] = children(der, root)
  if (!tbsNode || !algNode || !sigNode || sigNode.tag !== 0x03) throw new ProofError('Bad certificate')
  const tbsParts = children(der, tbsNode)
  // An explicit [0] version comes first in v3 certificates
  const fields = tbsParts[0]?.tag === 0xa0 ? tbsParts.slice(1) : tbsParts
  // serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
  const [, , issuer, validity, subject, spki] = fields
  if (!issuer || !validity || !subject || !spki) throw new ProofError('Bad certificate')
  const [notBefore, notAfter] = children(der, validity)
  const [spkiAlg] = children(der, spki)
  const spkiAlgParts = children(der, spkiAlg)
  const curveNode = spkiAlgParts[1]
  const curveOID = curveNode ? hex(der.slice(curveNode.contentStart, curveNode.end)) : ''
  const curve = curveOID === OID_P256 ? 'P-256' : curveOID === OID_P384 ? 'P-384' : null
  if (!curve) throw new ProofError('Unsupported certificate key')
  const algOID = children(der, algNode)[0]
  return {
    der,
    tbs: der.slice(tbsNode.start, tbsNode.end),
    signatureAlg: hex(der.slice(algOID.contentStart, algOID.end)),
    // A BIT STRING starts with its count of unused bits
    signature: der.slice(sigNode.contentStart + 1, sigNode.end),
    issuer: der.slice(issuer.start, issuer.end),
    subject: der.slice(subject.start, subject.end),
    notBefore: parseTime(der, notBefore),
    notAfter: parseTime(der, notAfter),
    spki: der.slice(spki.start, spki.end),
    curve,
  }
}

// DER SEQUENCE { INTEGER r, INTEGER s } to the r || s that WebCrypto verifies
function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const sequence = readNode(der, 0)
  const [r, s] = children(der, sequence)
  if (!r || !s) throw new ProofError('Bad signature')
  const out = new Uint8Array(size * 2)
  for (const [index, node] of [r, s].entries()) {
    let value = der.slice(node.contentStart, node.end)
    while (value.length > size && value[0] === 0) value = value.slice(1)
    if (value.length > size) throw new ProofError('Bad signature')
    out.set(value, index * size + (size - value.length))
  }
  return out
}

async function importKey(cert: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey('spki', cert.spki, { name: 'ECDSA', namedCurve: cert.curve }, false, ['verify'])
}

async function issuedBy(child: Certificate, issuer: Certificate): Promise<boolean> {
  if (!sameBytes(child.issuer, issuer.subject)) return false
  const hash = child.signatureAlg === OID_ECDSA_SHA256 ? 'SHA-256' : child.signatureAlg === OID_ECDSA_SHA384 ? 'SHA-384' : null
  if (!hash) return false
  const size = issuer.curve === 'P-256' ? 32 : 48
  return crypto.subtle.verify(
    { name: 'ECDSA', hash },
    await importKey(issuer),
    derSignatureToRaw(child.signature, size),
    child.tbs
  )
}

// MARK: Transactions

export interface ProTransaction {
  productId: string
  bundleId: string
  expiresDate?: number
  revocationDate?: number
}

// Verifies the JWS and returns its payload. Throws ProofError otherwise.
export async function verifySignedTransaction(
  jws: string,
  now = Date.now(),
  rootSha256 = APPLE_ROOT_CA_G3_SHA256
): Promise<ProTransaction> {
  const parts = jws.split('.')
  if (parts.length !== 3) throw new ProofError('Malformed transaction')
  let header: { alg?: string; x5c?: unknown }
  let payload: ProTransaction
  try {
    header = JSON.parse(dec.decode(b64ToBytes(parts[0])))
    payload = JSON.parse(dec.decode(b64ToBytes(parts[1])))
  } catch {
    throw new ProofError('Malformed transaction')
  }
  if (header.alg !== 'ES256') throw new ProofError('Unsupported algorithm')
  if (!Array.isArray(header.x5c) || header.x5c.length < 2 || header.x5c.length > 4) {
    throw new ProofError('Missing certificate chain')
  }
  const chain = header.x5c.map((entry) => {
    if (typeof entry !== 'string') throw new ProofError('Bad certificate')
    return parseCertificate(b64ToBytes(entry))
  })
  for (const cert of chain) {
    if (now < cert.notBefore || now > cert.notAfter) throw new ProofError('Certificate not valid now')
  }
  const root = chain[chain.length - 1]
  const fingerprint = hex(new Uint8Array(await crypto.subtle.digest('SHA-256', root.der)))
  if (fingerprint !== rootSha256) throw new ProofError('Not signed by Apple')
  for (let i = 0; i < chain.length - 1; i++) {
    if (!(await issuedBy(chain[i], chain[i + 1]))) throw new ProofError('Broken certificate chain')
  }
  const leaf = chain[0]
  if (leaf.curve !== 'P-256') throw new ProofError('Unsupported signing key')
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    await importKey(leaf),
    b64ToBytes(parts[2]),
    enc.encode(`${parts[0]}.${parts[1]}`)
  )
  if (!valid) throw new ProofError('Bad signature')
  if (!payload || typeof payload !== 'object') throw new ProofError('Malformed transaction')
  return payload
}

// True when the signed transaction is an active Pro plan for this app
export async function isActivePro(jws: string, bundleId: string, now = Date.now(), rootSha256?: string): Promise<boolean> {
  try {
    const transaction = await verifySignedTransaction(jws, now, rootSha256)
    if (transaction.bundleId !== bundleId) return false
    if (!PRO_PRODUCT_IDS.has(transaction.productId)) return false
    if (transaction.revocationDate) return false
    return typeof transaction.expiresDate === 'number' && transaction.expiresDate > now
  } catch {
    // A malformed chain can also fail inside WebCrypto; either way it's no proof
    return false
  }
}
