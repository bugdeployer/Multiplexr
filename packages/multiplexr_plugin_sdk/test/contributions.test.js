import test from 'node:test';
import assert from 'node:assert/strict';
import { contribution, validateContributionRequest as input, validateContributionResult as output } from '../src/contributions.js';
import { definePlugin, envelope, createHost } from '../src/sdk.js';
const ns = 'org.example.synthetic';
const nid = local => `${ns}:${local}`;
const scope = { scope: 'title', collection: 'collection-handle', entity: 'title-handle' };
const cases = [
  ['metadata.provider', { query: 'Moon', kind: 'ebook' }, { items: [{ id: nid('one'), title: 'Moon', authors: ['Author'] }], nextCursor: null }],
  ['artwork.provider', { title: 'title-handle', roles: ['cover'] }, { items: [{ id: nid('cover'), role: 'cover', attribution: 'Synthetic' }], nextCursor: null }],
  ['source.provider', { root: 'root-handle' }, { items: [{ id: nid('file'), name: 'Moon.txt', mime: 'text/plain' }], nextCursor: null }],
  ['import.handler', { input: 'input-handle', mime: 'application/json' }, { proposals: [{ title: 'title-handle', expectedRevision: '1', changes: { title: 'Moon' } }] }],
  ['export.handler', { selection: [{ id: 'title-handle', revision: '1' }] }, { name: 'titles.txt', mime: 'text/plain', text: 'Moon' }],
  ['library.tool', { selection: [{ id: 'title-handle', revision: '1' }] }, { proposals: [{ title: 'title-handle', expectedRevision: '1', changes: { authors: ['Author'] } }] }],
  ['event.handler', { event: nid('updated'), sequence: 1, data: {} }, { acknowledged: true }],
  ...['ui.action', 'ui.section', 'ui.destination'].map(family => [family, { scope }, { kind: 'group', children: [{ kind: 'action', label: 'Open', action: nid('open') }] }]),
  ['session.hook', { session: 'session-handle', state: { kind: 'text', section: 'chapter', offset: 10 } }, { commands: [{ kind: 'seek', position: { kind: 'time', milliseconds: 100 } }] }],
];
test('every executable family validates its own input and output contract', () => {
  for (const [family, params, result] of cases) {
    assert.deepEqual(input(family, params), params, family);
    assert.deepEqual(output(family, result, ns), result, family);
    const dispatch = definePlugin({ 'example.run': contribution(family, () => result, ns) });
    assert.deepEqual(dispatch({ v: 1, id: 'a', method: 'example.run', params }).result, result, family);
    assert.throws(() => input(family, { ...params, arbitrary: 'field' }), family);
    assert.throws(() => output(family, { arbitrary: 'field' }, ns), family);
  }
});
test('native handles, revisionless mutations, arbitrary UI and executable themes fail closed', () => {
  assert.throws(() => input('library.tool', { selection: [{ id: 'one' }] }));
  assert.throws(() => output('library.tool', { proposals: [{ title: 'one', changes: { title: 'Bad' } }] }));
  assert.throws(() => output('ui.section', { kind: 'html', text: '<script/>' }));
  assert.throws(() => output('ui.action', { kind: 'action', label: 'Host', action: 'org.other:open' }, ns));
  assert.throws(() => output('session.hook', { commands: [{ kind: 'native', method: 'open' }] }));
  assert.throws(() => output('session.hook', { commands: [{ kind: 'seek', position: { kind: 'time', milliseconds: -1 } }] }));
  for (const family of ['theme', 'settings.section']) assert.throws(() => input(family, {}), error => error.code === 'unsupported_capability');
});
test('envelopes reject unknown fields, ambiguous replies and oversized UTF-8 messages', () => {
  for (const params of [undefined, () => {}, { value: NaN }]) assert.throws(() => envelope({ v: 1, id: 'a', method: 'test.run', params }));
  assert.throws(() => envelope({ v: 1, id: 'a', method: 'test.run', params: {}, native: true }));
  assert.throws(() => envelope({ v: 1, id: 'a', result: 1, error: { code: 'plugin_error' } }, true));
  assert.throws(() => envelope({ v: 1, id: 'a', method: 'test.run', params: { a: '字'.repeat(24000) } }), error => error.code === 'message_too_large');
  const host = createHost(() => '{"v":1,"id":"h1","result":{},"unknown":true}');
  assert.throws(() => host.call('runtime.ping'), error => error.code === 'invalid_response');
  assert.throws(() => createHost(() => 'not-json').call('runtime.ping'), error => error.code === 'invalid_response');
});
test('invalid handler results use stable errors and disclose no thrown messages', () => {
  const dispatch = definePlugin({ 'tool.run': contribution('library.tool', () => ({ proposals: [{ title: 'x' }] })) });
  assert.deepEqual(dispatch({ v: 1, id: 'r1', method: 'tool.run', params: { selection: [] } }),
    { v: 1, id: 'r1', error: { code: 'invalid_response' } });
  const failed = definePlugin({ 'tool.run': () => { throw Error('secret'); } });
  assert.equal(JSON.stringify(failed({ v: 1, id: 'r2', method: 'tool.run', params: {} })).includes('secret'), false);
});
test('owned IDs and tool proposals cannot escape the declared namespace or selection', () => {
  assert.throws(() => output('metadata.provider', { items: [{ id: 'org.other:one', title: 'Other' }], nextCursor: null }, ns));
  const handler = contribution('library.tool', () => ({ proposals: [{ title: 'different', expectedRevision: 'one', changes: { title: 'No' } }] }));
  assert.throws(() => handler({ selection: [{ id: 'selected', revision: 'one' }] }, {}), error => error.code === 'invalid_response');
});
test('metadata requests preserve media semantics and bound identifier evidence', () => {
  for (const kind of ['movie', 'television', 'video', 'musicTrack', 'musicAlbum', 'audiobook', 'ebook', 'comic']) {
    input('metadata.provider', { query: 'Moon', kind, creator: 'Author', language: 'en', identifiers: [{ scheme: 'isbn', value: 'synthetic' }] });
  }
  assert.throws(() => input('metadata.provider', { query: 'Moon', kind: 'native' }));
  assert.throws(() => input('metadata.provider', { query: 'Moon', kind: 'ebook', identifiers: Array(17).fill({ scheme: 'isbn', value: 'x' }) }));
});
