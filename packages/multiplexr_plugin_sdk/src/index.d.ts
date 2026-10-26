export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type NamespacedId = `${string}:${string}`;
export type ErrorCode = 'invalid_request' | 'invalid_response' | 'version_mismatch' | 'unsupported_capability' | 'permission_denied' | 'not_found' | 'conflict' | 'cancelled' | 'deadline_exceeded' | 'resource_limit' | 'message_too_large' | 'busy' | 'plugin_error' | 'runtime_failure';
export class PluginError extends Error { readonly code: ErrorCode; constructor(code: ErrorCode, message?: string); }
export const protocolVersion: 1;
/** collection/entity are opaque invocation handles, never database identifiers. */
export type Scope = { scope: 'collection' | 'group' | 'title'; handle: string } | { scope: 'app' } | { scope: 'collection'; collection: string } | { scope: 'group' | 'title'; collection: string; entity: string };
export type Page<T> = { readonly items: readonly T[]; readonly nextCursor: string | null };
export interface Title { handle: string; id: string; collection: string; kind: 'movie' | 'television' | 'video' | 'music' | 'audiobook' | 'ebook' | 'comic'; title: string; revision: string; }
export type ReadingPosition = { kind: 'text'; section: string; offset: number } | { kind: 'page'; page: string; index: number; offset: number };
export type SessionPosition = ReadingPosition | { kind: 'time'; milliseconds: number };
export interface MetadataFields { description?: string; language?: string; identifier?: string; publisher?: string; publicationDate?: string; series?: string; volume?: string; issue?: string; year?: number; genres?: string[]; director?: string; narrator?: string; artist?: string; album?: string; }
export interface MetadataCandidate { id: NamespacedId; title: string; authors?: string[]; artwork?: string; fields?: MetadataFields; }
export interface MetadataProposal { title: string; expectedRevision: string; changes: { title?: string; authors?: string[]; description?: string }; }
export type SessionCommand = { kind: 'pause' | 'resume' } | { kind: 'seek'; position: SessionPosition };
export type ControlledNode = { kind: 'text'; text: string } | { kind: 'action'; label: string; action: NamespacedId } | { kind: 'group'; children: ControlledNode[] };
export type ContributionFamily = 'metadata.provider' | 'artwork.provider' | 'source.provider' | 'import.handler' | 'export.handler' | 'library.tool' | 'event.handler' | 'ui.action' | 'ui.section' | 'ui.destination' | 'settings.section' | 'theme' | 'session.hook' | 'media.descriptor';
export type SettingField = { id: NamespacedId; label: string; accessibleLabel: string; description?: string; scopes: Scope['scope'][]; visibleWhen?: Condition; enabledWhen?: Condition } & (
  { type: 'boolean'; default: boolean } | { type: 'number'; min: number; max: number; default: number } |
  { type: 'text'; maxLength: number; default: string } | { type: 'enum'; choices: string[]; default: string } |
  { type: 'multiSelect'; choices: string[]; default: string[] } | { type: 'credential' });
export interface Condition { field: NamespacedId; equals: string | number | boolean; }
export type Contribution = { id: NamespacedId; title: string } & (
  { family: Exclude<ContributionFamily, 'settings.section' | 'theme' | 'event.handler' | 'media.descriptor'>; handler: string } |
  { family: 'event.handler'; handler: string; events?: ('org.multiplexr:application.ready' | 'org.multiplexr:library.changed')[] } |
  { family: 'media.descriptor'; engine:'reader.epub'|'reader.text'|'reader.pdf'|'reader.comic'|'player.audio'|'player.video'; extensions:string[] } |
  { family: 'theme'; package: 'theme.json' } |
  { family: 'settings.section'; description: string; icon: 'settings' | 'book' | 'music' | 'video' | 'palette' | 'extension'; schemaVersion: 1; scopes: Scope['scope'][]; fields: SettingField[] });
export interface Manifest { id: string; version: string; name: string; entry: 'plugin.js'; protocol: { min: number; max: number }; capabilities: { required: string[]; optional: string[] }; contributions: Contribution[]; }
export interface EffectiveSetting<T extends Json = Json> { value: T; source: Scope | null; revision: number; }
export interface HostMethods {
  'catalog.fields': {params:{handle:string};result:Record<NamespacedId,Json>};
  'catalog.propose': {params:{handle:string;revision:string;idempotencyKey:string} & ({operation:'mergeFields';fields:Record<NamespacedId,Json>} | {operation:'replaceTags';tags:string[]});result:{proposal:string;status:'awaitingConfirmation'}};
  'http.get': {params:{url:string;credential?:boolean};result:{status:number;body:string}};
  'storage.read': {params:{schema:number;key:string};result:string|null};
  'storage.write': {params:{schema:number;key:string;value:string|null};result:null};
  'imports.read': {params:{handle:string};result:{text:string;mime:string}};
  'catalog.title': {params:{handle:string};result:Title};
  'runtime.ping': { params: {}; result: { protocol: 1; runtime: string } };
  'settings.register': { params: {}; result: { sections: NamespacedId[] } };
  'settings.effective': { params: { id: NamespacedId; lineage: Scope[] }; result: EffectiveSetting };
  'settings.propose': { params: { id: NamespacedId; address: Scope; value: Json; expectedRevision: number }; result: { revision: number } };
  'settings.reset': { params: { id: NamespacedId; address: Scope; expectedRevision: number }; result: { revision: number } };
  'settings.changes': { params: { afterRevision: number }; result: { events: { id: NamespacedId; address: Scope; revision: number }[]; resyncRequired: boolean; revision: number } };
  'catalog.titles': { params: { handle?: string; collection?: string; limit?: number; cursor?: string | null }; result: Page<Title> };
}
export interface Host { call<M extends keyof HostMethods>(method: M, params: HostMethods[M]['params'], cancellation?: Cancellation): HostMethods[M]['result']; }
export interface Request { v: 1; id: string; method: string; params: Json; }
export type Response = { v: 1; id: string; result: Json } | { v: 1; id: string | null; error: { code: ErrorCode } };
export class Cancellation { readonly cancelled: boolean; cancel(): void; check(): void; }
export function namespacedId(owner: string, local: string): NamespacedId;
export function page<T>(items: T[], nextCursor?: string | null): Page<T>;
export function request(id: string, method: string, params?: Json): Request;
export function createHost(transport: (json: string) => string): Host;
export function definePlugin(handlers: Record<string, (params: Json, host: Host) => Json>): (request: Request) => Response;
export function negotiate(requested: { min: number; max: number }, offered: { min: number; max: number }): number;
export function negotiateCapabilities(required: string[], optional: string[], offered: string[]): readonly string[];
export const families: readonly ContributionFamily[];
export const errorCodes: readonly ErrorCode[];
export function requireValue(condition: unknown, message: string): asserts condition;
export function validateJson(value: unknown, depth?: number): void;
export function byteLength(value: string): number;
export function envelope(value: unknown, response?: boolean): Request | Response;
