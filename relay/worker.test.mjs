import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('./worker.js', import.meta.url), 'utf8');
const { default: worker } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const request = (body, headers = { 'content-type': 'application/json' }) => new Request('https://example.test/report', { method: 'POST', headers, body });
const env = () => ({ REPO: 'example/app', GITHUB_TOKEN: 'unused', LIMITS: { get: async () => '0', put: async () => {} } });
test('rejects oversized and malformed request bodies before filing', async () => {
  assert.equal((await worker.fetch(request('x'.repeat(17000)), env())).status, 413);
  assert.equal((await worker.fetch(request('[]'), env())).status, 400);
  assert.equal((await worker.fetch(request('null'), env())).status, 400);
  assert.equal((await worker.fetch(request('{'), env())).status, 400);
  assert.equal((await worker.fetch(request('{}', {}), env())).status, 415);
});
test('requires configuration and honors quota and honeypot', async () => {
  const body = JSON.stringify({ text: 'A useful problem report' });
  assert.equal((await worker.fetch(request(body), {})).status, 503);
  const limited = env(); limited.LIMITS.get = async () => '10';
  assert.equal((await worker.fetch(request(body), limited)).status, 429);
  const bot = await worker.fetch(request(JSON.stringify({ text: 'A useful problem report', website: 'filled' })), env());
  assert.equal((await bot.json()).number, 0);
});
test('quotes user text and neutralizes mentions in issue title and body', async () => {
  const original = globalThis.fetch; let filed;
  globalThis.fetch = async (_url, options) => { filed = JSON.parse(options.body); return new Response(JSON.stringify({ number: 12 }), { status: 201 }); };
  try {
    const result = await worker.fetch(request(JSON.stringify({ text: '@someone\n---\nScreen: forged', version: '1\nforged' })), env());
    assert.equal(result.status, 200);
    assert.ok(filed.body.startsWith('> @\u200bsomeone\n> ---\n> Screen: forged'));
    assert.ok(!filed.title.includes('@someone'));
    assert.ok(filed.body.includes('App version: 1 forged'));
  } finally { globalThis.fetch = original; }
});
