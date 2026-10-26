import { createHost, namespacedId, type Manifest, type SessionPosition, type ControlledNode } from '../src/sdk.js';
import * as AppShell from '../src/app-shell.js';
const neutralId: string = AppShell.namespacedId('org.example.notes', 'enabled');
void neutralId;
const host = createHost(() => '{"result":{}}');
host.call('settings.effective', { id: namespacedId('org.example.synthetic', 'enabled'), lineage: [{ scope: 'app' }] });
// @ts-expect-error A title address must have collection and entity identities.
host.call('settings.effective', { id: 'org.example:enabled', lineage: [{ scope: 'title' }] });
// @ts-expect-error Raw native access is not an SDK capability.
host.call('native.files.read', {});
const location: SessionPosition = { kind: 'text', section: 'chapter1', offset: 50 };
const node: ControlledNode = { kind: 'text', text: 'Hello' };
const manifest: Manifest = { id: 'org.example.synthetic', version: '1.0.0', name: 'Example', entry: 'plugin.js', protocol: { min: 1, max: 1 }, capabilities: { required: [], optional: [] }, contributions: [] };
void [location, node, manifest];
import { contribution } from '../src/contributions.js';
contribution('source.provider', params => ({ items: [{ id: namespacedId('org.example.synthetic', 'file'), name: params.root, mime: 'text/plain' }], nextCursor: null }));
// @ts-expect-error Library tools require revision-scoped proposals, not direct writes.
contribution('library.tool', () => ({ writeDatabase: true }));
// @ts-expect-error Themes are declarative packages, not executable hooks.
contribution('theme', () => ({}));

host.call('http.get', {url:'https://example.com',credential:true});
host.call('storage.write', {schema:1,key:'cache',value:'cached'});
const cached: string|null = host.call('storage.read', {schema:1,key:'cache'});
host.call('catalog.propose', {operation:'replaceTags',handle:'opaque',revision:'r',tags:['favorite'],idempotencyKey:'edit1'});
// @ts-expect-error Network calls cannot receive a script-provided secret.
host.call('http.get', {url:'https://example.com',credential:'secret'});
// @ts-expect-error Tag proposals cannot omit revision checking.
host.call('catalog.propose', {operation:'replaceTags',handle:'opaque',tags:[],idempotencyKey:'edit2'});
void cached;
