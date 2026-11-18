// Checks the AI board's output validation and its guard rails, without
// calling Claude or Unsplash.
import assert from 'node:assert/strict'
import { AIError, clientIP, globalLimits, handleAI, parseDrafts, toSearchPhotos } from '../src/ai.ts'

const item = (text: string, photo_query = 'mountain lake sunrise') => ({ text, photo_query })
const six = Array.from({ length: 6 }, (_, i) => item(`I hike a new trail number ${i + 1}`))

// Valid output passes and is trimmed
const ok = parseDrafts(JSON.stringify({ items: [item('  I read  24 books '), ...six] }), 8)
assert.equal(ok.length, 7)
assert.equal(ok[0].text, 'I read 24 books')

// Stops at the requested count
assert.equal(parseDrafts(JSON.stringify({ items: [...six, item('I learn to surf'), item('I sleep 8 hours')] }), 6).length, 6)

// Drops clippings that are too long, empty or repeated, then needs six
const tooLong = item('x'.repeat(61))
assert.throws(() => parseDrafts(JSON.stringify({ items: [...six.slice(0, 5), tooLong, item(''), six[0]] }), 8), AIError)

// Rejects anything that isn't the schema
assert.throws(() => parseDrafts('not json', 8), AIError)
assert.throws(() => parseDrafts(JSON.stringify({ goals: six }), 8), AIError)
assert.throws(() => parseDrafts(JSON.stringify({ items: [1, 2, 3, 4, 5, 6] }), 8), AIError)

// Em dashes never reach the board
assert.ok(!parseDrafts(JSON.stringify({ items: [item('I travel — and rest'), ...six] }), 8)[0].text.includes('—'))

// Guard rails run before any network call or database write
const env = { DB: undefined as unknown as D1Database }
const post = (headers: Record<string, string> = {}) =>
  new Request('https://x/api/sync/ai/board', { method: 'POST', headers, body: JSON.stringify({ prompt: 'hi', lang: 'en' }) })

assert.equal(await handleAI(post(), env, '/board'), null)
assert.equal((await handleAI(post(), env, '/ai/board'))!.status, 403)
const unavailable = await handleAI(post({ 'X-VB-Client': 'ios' }), env, '/ai/board')
assert.equal(unavailable!.status, 503)
assert.deepEqual(await unavailable!.json(), { error: 'ai_unavailable' })

// Create with AI is Pro on the server too: no signed transaction, no board
const configuredEnv = { DB: undefined as unknown as D1Database, ANTHROPIC_API_KEY: 'k', UNSPLASH_ACCESS_KEY: 'u' }
const noProof = await handleAI(post({ 'X-VB-Client': 'ios' }), configuredEnv, '/ai/board')
assert.equal(noProof!.status, 402)
assert.deepEqual(await noProof!.json(), { error: 'pro_required' })
const badProof = await handleAI(post({ 'X-VB-Client': 'ios', 'X-VB-Pro': 'a.b.c' }), configuredEnv, '/ai/board')
assert.equal(badProof!.status, 402)

// X-Forwarded-For only counts with the proxy's secret once one is set
const headers = (h: Record<string, string>) => new Request('https://x/', { headers: h })
assert.equal(clientIP(headers({ 'CF-Connecting-IP': '1.1.1.1', 'X-Forwarded-For': '9.9.9.9' })), '9.9.9.9')
assert.equal(clientIP(headers({ 'CF-Connecting-IP': '1.1.1.1', 'X-Forwarded-For': '9.9.9.9' }), 'secret'), '1.1.1.1')
assert.equal(
  clientIP(headers({ 'CF-Connecting-IP': '1.1.1.1', 'X-Forwarded-For': '9.9.9.9, 2.2.2.2', 'X-VB-Proxy': 'secret' }), 'secret'),
  '9.9.9.9'
)
assert.equal(clientIP(headers({ 'CF-Connecting-IP': '1.1.1.1', 'X-Forwarded-For': '9.9.9.9', 'X-VB-Proxy': 'wrong!' }), 'secret'), '1.1.1.1')

// Global caps follow the Unsplash quota: a board can make up to 9 searches
assert.deepEqual(globalLimits({}), { boards: 222, searches: 1000, downloads: 2000 })
assert.deepEqual(globalLimits({ UNSPLASH_HOURLY_QUOTA: '50' }), { boards: 2, searches: 10, downloads: 20 })

// Photo search: web and iOS may search, only the Unsplash key is needed
const search = (headers: Record<string, string>, body: unknown = { query: 'beach house' }) =>
  new Request('https://x/api/sync/ai/photos', { method: 'POST', headers, body: JSON.stringify(body) })
assert.equal((await handleAI(search({}), env, '/ai/photos'))!.status, 403)
assert.equal((await handleAI(search({ 'X-VB-Client': 'web' }), env, '/ai/photos'))!.status, 503)
const unsplashOnly = { DB: undefined as unknown as D1Database, UNSPLASH_ACCESS_KEY: 'u' }
assert.equal((await handleAI(search({ 'X-VB-Client': 'web' }, { query: '  ' }), unsplashOnly, '/ai/photos'))!.status, 400)
assert.equal((await handleAI(search({ 'X-VB-Client': 'ios' }, { query: 'x'.repeat(81) }), unsplashOnly, '/ai/photos'))!.status, 400)
assert.equal((await handleAI(search({ 'X-VB-Client': 'web' }, { query: 'sea', page: 11 }), unsplashOnly, '/ai/photos'))!.status, 400)
// The web still can't make AI boards
assert.equal((await handleAI(new Request('https://x/', { method: 'POST', headers: { 'X-VB-Client': 'web' }, body: '{}' }), configuredEnv, '/ai/board'))!.status, 403)

// Search results keep only Unsplash CDN photos with a size
const cdn = 'https://images.unsplash.com/photo-1'
const photos = toSearchPhotos([
  { width: 4000, height: 6000, urls: { regular: cdn, small: cdn + '?w=400' }, user: { name: ' Ana ', links: { html: 'https://unsplash.com/@ana' } }, links: { download_location: 'https://api.unsplash.com/photos/a/download' } },
  { width: 10, height: 10, urls: { regular: 'https://evil.example/x.jpg' } },
  { urls: { regular: cdn } },
])
assert.equal(photos.length, 1)
assert.equal(photos[0].photographer, 'Ana')
assert.equal(photos[0].photographerUrl, 'https://unsplash.com/@ana?utm_source=visionboard&utm_medium=referral')
assert.equal(photos[0].thumbUrl, cdn + '?w=400')

console.log('ai ok')
