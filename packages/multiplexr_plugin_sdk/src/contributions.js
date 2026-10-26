import { PluginError, requireValue, validateJson, page, families } from './sdk.js';

const text = (value, maximum = 256) => typeof value === 'string' && value.length > 0 && value.length <= maximum;
const id = value => text(value, 161) && /^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+:[a-z][a-zA-Z0-9_.-]{0,79}$/.test(value);
function record(value) { requireValue(value && typeof value === 'object' && !Array.isArray(value), 'Object required'); }
function keys(value, required, optional = []) {
  record(value);
  requireValue(required.every(key => Object.hasOwn(value, key)) && Object.keys(value).every(key => [...required, ...optional].includes(key)), 'Invalid fields');
}
function list(value, validate, maximum = 100) {
  requireValue(Array.isArray(value) && value.length <= maximum, 'Bounded list required');
  value.forEach(validate);
}
function position(value) {
  record(value);
  if (value.kind === 'time') {
    keys(value, ['kind', 'milliseconds']);
    requireValue(Number.isSafeInteger(value.milliseconds) && value.milliseconds >= 0, 'Invalid time');
  } else if (value.kind === 'text') {
    keys(value, ['kind', 'section', 'offset']);
    requireValue(text(value.section) && Number.isSafeInteger(value.offset) && value.offset >= 0, 'Invalid text locator');
  } else {
    keys(value, ['kind', 'page', 'index', 'offset']);
    requireValue(value.kind === 'page' && text(value.page) && Number.isSafeInteger(value.index) && value.index >= 0 &&
      Number.isFinite(value.offset) && value.offset >= 0 && value.offset <= 1, 'Invalid page locator');
  }
}
function node(value, owner, depth = 0) {
  record(value); requireValue(depth <= 8, 'UI nesting limit');
  if (value.kind === 'text') {
    keys(value, ['kind', 'text']); requireValue(typeof value.text === 'string' && value.text.length <= 4096, 'Invalid text node');
  } else if (value.kind === 'action') {
    keys(value, ['kind', 'label', 'action']); requireValue(text(value.label) && id(value.action) && (!owner || value.action.startsWith(`${owner}:`)), 'Invalid action node');
  } else {
    keys(value, ['kind', 'children']); requireValue(value.kind === 'group', 'Unsupported UI node');
    list(value.children, child => node(child, owner, depth + 1), 32);
  }
}
function candidate(value) {
  keys(value, ['id', 'title'], ['authors', 'artwork','fields']);
  if(value.fields!==undefined) {
    keys(value.fields,[],['description','language','identifier','publisher','publicationDate','series','volume','issue','year','genres','director','narrator','artist','album']);
    for(const [key,field] of Object.entries(value.fields)) {
      if(key==='year') requireValue(Number.isInteger(field)&&field>=0&&field<=9999,'Invalid year');
      else if(key==='genres') list(field,v=>requireValue(text(v,100),'Invalid genre'));
      else requireValue(text(field,key==='description'?8192:512),'Invalid metadata field');
    }
  }
  requireValue(id(value.id) && text(value.title, 512), 'Invalid metadata candidate');
  if (value.authors) list(value.authors, author => requireValue(text(author), 'Invalid author'), 32);
  if (value.artwork) requireValue(id(value.artwork), 'Artwork handle required');
}
function artwork(value) {
  keys(value, ['id', 'role', 'attribution'], ['content','url']);
  if(value.content!==undefined) requireValue(typeof value.content==='string' && value.content.startsWith('data:image/png;base64,') && value.content.length<=32768 && value.url===undefined,'Invalid inline artwork');
  if(value.url!==undefined) requireValue(typeof value.url==='string' && value.url.startsWith('https://') && value.url.length<=4096 && value.content===undefined,'Invalid artwork URL');
  requireValue(id(value.id) && ['cover', 'poster', 'backdrop', 'thumbnail'].includes(value.role) && text(value.attribution, 1000), 'Invalid artwork');
}
function pageResult(value, validate) {
  keys(value, ['items', 'nextCursor']); page(value.items, value.nextCursor); list(value.items, validate);
}
function proposal(value) {
  keys(value, ['title', 'expectedRevision', 'changes']);
  requireValue(text(value.title) && text(value.expectedRevision), 'Revision-scoped title required');
  keys(value.changes, [], ['title', 'authors', 'description']);
  requireValue(Object.keys(value.changes).length > 0, 'Empty metadata proposal');
  for (const [key, field] of Object.entries(value.changes)) {
    if (key === 'authors') list(field, author => requireValue(text(author), 'Invalid author'), 32);
    else requireValue(typeof field === 'string' && field.length <= (key === 'description' ? 8192 : 512), 'Invalid metadata field');
  }
}
export function validateContributionRequest(family, value) {
  requireValue(families.includes(family), 'Unknown contribution family'); validateJson(value); record(value);
  if (family === 'metadata.provider') {
    keys(value, ['query', 'kind'], ['cursor', 'creator', 'language', 'identifiers']);
    requireValue(text(value.query, 1024) && ['movie', 'television', 'video', 'musicTrack', 'musicAlbum', 'audiobook', 'ebook', 'comic'].includes(value.kind), 'Query and media kind required');
    if (value.creator !== undefined) requireValue(typeof value.creator === 'string' && value.creator.length <= 512, 'Invalid creator');
    if (value.language !== undefined) requireValue(text(value.language, 35), 'Invalid language');
    if (value.identifiers !== undefined) list(value.identifiers, identifier => {
      keys(identifier, ['scheme', 'value']); requireValue(text(identifier.scheme, 32) && text(identifier.value, 256), 'Invalid identifier');
    }, 16);
  } else if (family === 'artwork.provider') {
    keys(value, ['title', 'roles'], ['cursor']); requireValue(text(value.title), 'Title handle required');
    list(value.roles, role => requireValue(['cover', 'poster', 'backdrop', 'thumbnail'].includes(role), 'Invalid role'), 4);
  } else if (family === 'source.provider') {
    keys(value, ['root'], ['cursor']); requireValue(text(value.root), 'Granted root handle required');
  } else if (family === 'import.handler') {
    keys(value, ['input', 'mime'],['selection']); requireValue(text(value.input) && text(value.mime), 'Granted input handle required');
    if(value.selection!==undefined) list(value.selection,item=>{keys(item,['id','revision']);requireValue(text(item.id)&&text(item.revision),'Selection required');});
  } else if (['export.handler', 'library.tool'].includes(family)) {
    keys(value, ['selection']); list(value.selection, entry => {
      keys(entry, ['id', 'revision']); requireValue(text(entry.id) && text(entry.revision), 'Revision-scoped selection required');
    });
  } else if (family === 'event.handler') {
    keys(value, ['event', 'sequence', 'data']); requireValue(id(value.event) && Number.isSafeInteger(value.sequence) && value.sequence >= 0, 'Invalid event');
  } else if (family.startsWith('ui.')) {
    keys(value, ['scope']); record(value.scope);
    requireValue(['app', 'collection', 'group', 'title'].includes(value.scope.scope), 'Invalid UI scope');
    if (value.scope.scope !== 'app') requireValue(text(value.scope.collection), 'Collection handle required');
    if (['group', 'title'].includes(value.scope.scope)) requireValue(text(value.scope.entity), 'Entity handle required');
  } else if (family === 'settings.section') {
    throw new PluginError('unsupported_capability', 'Settings are declarative manifest contributions');
  } else if (['theme','media.descriptor'].includes(family)) {
    throw new PluginError('unsupported_capability', 'Themes are data-only packages, not executable handlers');
  } else {
    keys(value, ['session', 'state']); requireValue(text(value.session), 'Session handle required'); position(value.state);
  }
  if (Object.hasOwn(value, 'cursor')) requireValue(value.cursor === null || typeof value.cursor === 'string' && value.cursor.length <= 256, 'Invalid cursor');
  return value;
}
export function validateContributionResult(family, value, owner) {
  validateJson(value);
  if (family === 'metadata.provider') pageResult(value, candidate);
  else if (family === 'artwork.provider') pageResult(value, artwork);
  else if (family === 'source.provider') pageResult(value, entry => {
    keys(entry, ['id', 'name', 'mime']); requireValue(id(entry.id) && text(entry.name) && text(entry.mime), 'Invalid discovered item');
  });
  else if (['import.handler', 'library.tool'].includes(family)) {
    keys(value, ['proposals']); list(value.proposals, proposal);
  } else if (family === 'export.handler') {
    keys(value, ['name', 'mime', 'text']); requireValue(text(value.name) && !/[\\/]/.test(value.name) && text(value.mime) &&
      typeof value.text === 'string' && value.text.length <= 32768, 'Invalid export');
  } else if (family === 'event.handler') {
    keys(value, ['acknowledged']); requireValue(typeof value.acknowledged === 'boolean', 'Invalid event acknowledgement');
  } else if (family.startsWith('ui.')) node(value, owner);
  else if (family === 'session.hook') {
    keys(value, ['commands']); list(value.commands, command => {
      if (command.kind === 'seek') { keys(command, ['kind', 'position']); position(command.position); }
      else { keys(command, ['kind']); requireValue(['pause', 'resume'].includes(command.kind), 'Unsupported session command'); }
    }, 8);
  } else throw new PluginError('unsupported_capability');
  if (owner && ['metadata.provider', 'artwork.provider', 'source.provider'].includes(family)) {
    requireValue(value.items.every(item => item.id.startsWith(`${owner}:`)), 'Contribution namespace mismatch');
  }
  return value;
}
export function contribution(family, handler, owner) {
  return (params, host) => {
    validateContributionRequest(family, params);
    const result = handler(params, host);
    try {
      validateContributionResult(family, result, owner);
      if (family === 'library.tool') requireValue(result.proposals.every(proposal =>
        params.selection.some(selected => selected.id === proposal.title && selected.revision === proposal.expectedRevision)), 'Proposal outside revision-scoped selection');
      return result;
    }
    catch (_) { throw new PluginError('invalid_response'); }
  };
}
