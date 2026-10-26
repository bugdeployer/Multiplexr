import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, cp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { FakeHost } from '../src/fake-host.js';
import { validateManifest } from '../src/manifest.js';
import { PluginError, namespacedId, negotiate, negotiateCapabilities, Cancellation, createHost, page, validateJson } from '../src/sdk.js';
import { build, validate } from '../bin/plugin.js';
const manifest = JSON.parse(await readFile(new URL('../examples/synthetic/manifest.json', import.meta.url)));
const id = name => `org.example.synthetic:${name}`;
const failure = code => error => error instanceof PluginError && error.code === code;
test('namespaces, version and capability negotiation fail closed', () => {
  assert.equal(namespacedId(manifest.id, 'item'), id('item'));
  assert.throws(() => namespacedId('../host', 'item'));
  assert.throws(() => negotiate({ min: 2, max: 3 }, { min: 1, max: 1 }), failure('version_mismatch'));
  assert.throws(() => negotiateCapabilities(['native.codec'], [], ['runtime.ping']), failure('unsupported_capability'));
  assert.deepEqual(negotiateCapabilities([], ['native.codec', 'runtime.ping'], ['runtime.ping']), ['runtime.ping']);
});
test('manifest rejects cross namespace definitions, secret defaults and invalid constraints', () => {
  assert.deepEqual(validateManifest(manifest), manifest);
  for (const change of [m => m.contributions[1].fields[0].id = 'host:enabled', m => m.contributions[1].fields[2].default = 'secret', m => m.contributions[1].fields[1].default = 999, m => m.entry = '../outside.js']) {
    const copy = structuredClone(manifest); change(copy); assert.throws(() => validateManifest(copy));
  }
});
test('settings scope inheritance, provenance, optimistic changes and reset', () => {
  const host = new FakeHost(manifest, { collections: ['books'] });
  const app = { scope: 'app' }, collection = { scope: 'collection', collection: 'books' };
  const effective = () => host.call('settings.effective', { id: id('enabled'), lineage: [app, collection] });
  assert.deepEqual(effective(), { value: true, source: null, revision: 0 });
  host.call('settings.propose', { id: id('enabled'), address: app, value: false, expectedRevision: 0 });
  host.call('settings.propose', { id: id('enabled'), address: collection, value: true, expectedRevision: 1 });
  assert.deepEqual(effective(), { value: true, source: collection, revision: 2 });
  assert.throws(() => host.call('settings.reset', { id: id('enabled'), address: collection, expectedRevision: 1 }), failure('conflict'));
  host.call('settings.reset', { id: id('enabled'), address: collection, expectedRevision: 2 });
  assert.deepEqual(effective(), { value: false, source: app, revision: 3 });
});
test('invalid changes are atomic, secrets and ungranted scopes never escape', () => {
  const host = new FakeHost(manifest, { collections: ['books'] });
  assert.throws(() => host.call('settings.propose', { id: id('limit'), address: { scope: 'app' }, value: 101, expectedRevision: 0 }));
  assert.equal(host.call('settings.changes', { afterRevision: 0 }).revision, 0);
  assert.throws(() => host.call('settings.effective', { id: id('credential'), lineage: [{ scope: 'app' }] }), failure('permission_denied'));
  assert.throws(() => host.call('settings.effective', { id: id('enabled'), lineage: [{ scope: 'collection', collection: 'locked' }] }), failure('permission_denied'));
  assert.throws(() => host.call('settings.effective', { id: id('enabled'), lineage: [{ scope: 'title', collection: 'books', entity: 'a' }, { scope: 'app' }] }));
});
test('postcommit event queue is bounded and indicates resync; disable revokes calls', () => {
  const host = new FakeHost(manifest);
  for (let i = 0; i < 100; i++) host.call('settings.propose', { id: id('enabled'), address: { scope: 'app' }, value: !!(i % 2), expectedRevision: i });
  const changes = host.call('settings.changes', { afterRevision: 0 });
  assert.equal(changes.events.length, 32); assert.equal(changes.resyncRequired, true);
  assert.equal(JSON.stringify(changes).includes('value'), false);
  host.disable(); assert.throws(() => host.call('runtime.ping'), failure('permission_denied'));
});
test('cancellation, pagination, nesting and wire versions are checked', () => {
  const fake = new FakeHost(manifest), host = createHost(fake.transport), cancel = new Cancellation();
  cancel.cancel(); assert.throws(() => host.call('runtime.ping', {}, cancel), failure('cancelled'));
  assert.throws(() => page(Array(101).fill(1)));
  let nested = 1; for (let i = 0; i < 26; i++) nested = [nested]; assert.throws(() => validateJson(nested));
  assert.equal(JSON.parse(fake.transport('{"v":2}')).error.code, 'version_mismatch');
  assert.throws(() => host.call('native.files.read', {}), failure('unsupported_capability'));
});
test('standalone copied SDK builds without app source and detects tampering', async () => {
  const temp = await mkdtemp(join(tmpdir(), 'multiplexr-sdk-'));
  const sdk = join(temp, 'sdk');
  await cp(new URL('..', import.meta.url), sdk, { recursive: true, filter: source => !source.includes('node_modules') && !source.includes('dist') });
  const output = join(temp, 'synthetic.json');
  execFileSync(process.execPath, [join(sdk, 'bin/plugin.js'), 'build', join(sdk, 'examples/synthetic'), output]);
  const artifact = await validate(output);
  assert.match(artifact.code, /metadata.search/);
  artifact.code += ' // changed'; await writeFile(output, JSON.stringify(artifact));
  await assert.rejects(validate(output));
});
test('build does not execute author code or overwrite existing output', async () => {
  const temp = await mkdtemp(join(tmpdir(), 'multiplexr-untrusted-'));
  await writeFile(join(temp, 'manifest.json'), JSON.stringify(manifest));
  await writeFile(join(temp, 'plugin.js'), 'throw new Error("must never execute on build")');
  const output = join(temp, 'plugin.json'); await build(temp, output);
  await assert.rejects(build(temp, output));
});

test('fake host enforces declared and offered grants instead of granting every method', () => {
  const readOnly = new FakeHost(manifest, { offeredCapabilities: ['runtime.ping', 'settings.read'] });
  assert.throws(() => readOnly.call('settings.propose', { id: id('enabled'), address: { scope: 'app' }, value: true, expectedRevision: 0 }), failure('permission_denied'));
  const undeclared = structuredClone(manifest); undeclared.capabilities.optional = [];
  assert.throws(() => new FakeHost(undeclared).call('settings.register'), failure('permission_denied'));
  const required = structuredClone(manifest); required.capabilities.required.push('native.files');
  assert.throws(() => new FakeHost(required), failure('unsupported_capability'));
});

test('settings condition cycles and executable theme declarations are rejected', () => {
  const cyclic = structuredClone(manifest), fields = cyclic.contributions[1].fields;
  fields[0].enabledWhen = { field: fields[1].id, equals: 10 };
  assert.throws(() => validateManifest(cyclic));
  const theme = structuredClone(manifest);
  theme.contributions = [{ id: id('theme'), family: 'theme', title: 'Theme', handler: 'theme.execute' }];
  assert.throws(() => validateManifest(theme));
  theme.contributions = [{ id: id('theme'), family: 'theme', title: 'Theme', package: 'theme.json' }];
  validateManifest(theme);
});
