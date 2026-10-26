import type { Host, Page, Scope, Json, NamespacedId, SessionPosition, SessionCommand, ControlledNode, MetadataCandidate, MetadataProposal } from './index.js';
export interface ContributionMethods {
  'metadata.provider': { params: { query: string; kind: 'movie' | 'television' | 'video' | 'musicTrack' | 'musicAlbum' | 'audiobook' | 'ebook' | 'comic'; creator?: string; language?: string; identifiers?: { scheme: string; value: string }[]; cursor?: string | null }; result: Page<MetadataCandidate> };
  'artwork.provider': { params: { title: string; roles: ('cover' | 'poster' | 'backdrop' | 'thumbnail')[]; cursor?: string | null }; result: Page<{ id: NamespacedId; role: 'cover' | 'poster' | 'backdrop' | 'thumbnail'; attribution: string; content?: string; url?: string }> };
  'source.provider': { params: { root: string; cursor?: string | null }; result: Page<{ id: NamespacedId; name: string; mime: string }> };
  'import.handler': { params: { input: string; mime: string; selection?: {id:string;revision:string}[] }; result: { proposals: MetadataProposal[] } };
  'export.handler': { params: { selection: { id: string; revision: string }[] }; result: { name: string; mime: string; text: string } };
  'library.tool': { params: { selection: { id: string; revision: string }[] }; result: { proposals: MetadataProposal[] } };
  'event.handler': { params: { event: NamespacedId; sequence: number; data: Json }; result: { acknowledged: boolean } };
  'ui.action': { params: { scope: Scope }; result: ControlledNode };
  'ui.section': { params: { scope: Scope }; result: ControlledNode };
  'ui.destination': { params: { scope: Scope }; result: ControlledNode };
  'session.hook': { params: { session: string; state: SessionPosition }; result: { commands: SessionCommand[] } };
}
export function validateContributionRequest<F extends keyof ContributionMethods>(family: F, value: unknown): ContributionMethods[F]['params'];
export function validateContributionResult<F extends keyof ContributionMethods>(family: F, value: unknown, owner?: string): ContributionMethods[F]['result'];
export function contribution<F extends keyof ContributionMethods>(family: F,
  handler: (params: ContributionMethods[F]['params'], host: Host) => ContributionMethods[F]['result'], owner?: string):
  (params: Json, host: Host) => Json;
