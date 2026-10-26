import { families, namespacedId, requireValue, negotiate, validateJson } from './sdk.js';

const scopes = ['app', 'collection', 'group', 'title'];
const types = ['boolean', 'number', 'text', 'enum', 'multiSelect', 'credential'];
const text = (v, max = 200) => typeof v === 'string' && v.length > 0 && v.length <= max;
function keys(value, allowed) {
  requireValue(value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).every(k => allowed.includes(k)), 'Unknown field');
}
export function validateField(field, owner, sectionScopes) {
  keys(field, ['id', 'type', 'label', 'description', 'accessibleLabel', 'default', 'scopes', 'min', 'max', 'maxLength', 'choices', 'visibleWhen', 'enabledWhen']);
  requireValue(field.id === namespacedId(owner, field.id?.split(':')[1]) && types.includes(field.type) && text(field.label) && text(field.accessibleLabel), 'Invalid field');
  requireValue(Array.isArray(field.scopes) && field.scopes.length > 0 && new Set(field.scopes).size === field.scopes.length && field.scopes.every(s => sectionScopes.includes(s)), 'Invalid field scopes');
  if (field.type === 'number') requireValue(Number.isFinite(field.min) && Number.isFinite(field.max) && field.min <= field.max, 'Number bounds required');
  if (field.type === 'text') requireValue(Number.isInteger(field.maxLength) && field.maxLength > 0 && field.maxLength <= 4096, 'Text bound required');
  if (['enum', 'multiSelect'].includes(field.type)) requireValue(Array.isArray(field.choices) && field.choices.length > 0 && field.choices.length <= 100 && new Set(field.choices).size === field.choices.length && field.choices.every(c => text(c, 100)), 'Invalid choices');
  if (field.type === 'credential') requireValue(!Object.hasOwn(field, 'default'), 'Credentials cannot have serialized defaults');
  else validateSettingValue(field, field.default);
  for (const condition of [field.visibleWhen, field.enabledWhen].filter(Boolean)) {
    keys(condition, ['field', 'equals']);
    requireValue(typeof condition.field === 'string' && condition.field.startsWith(`${owner}:`), 'Condition namespace');
    requireValue(['string', 'boolean', 'number'].includes(typeof condition.equals), 'Scalar condition required');
  }
}
export function validateSettingValue(field, value) {
  const valid = field.type === 'boolean' ? typeof value === 'boolean' :
    field.type === 'number' ? Number.isFinite(value) && value >= field.min && value <= field.max :
    field.type === 'text' ? typeof value === 'string' && value.length <= field.maxLength :
    field.type === 'enum' ? field.choices.includes(value) :
    field.type === 'multiSelect' ? Array.isArray(value) && value.length <= field.choices.length && new Set(value).size === value.length && value.every(v => field.choices.includes(v)) : false;
  requireValue(valid, 'Invalid setting value; credentials require host setup');
}
export function validateManifest(m) {
  validateJson(m);
  keys(m, ['id', 'version', 'name', 'protocol', 'entry', 'capabilities', 'contributions']);
  namespacedId(m.id, 'check');
  requireValue(text(m.name) && text(m.version, 80) && /^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$/.test(m.version), 'Invalid package metadata');
  requireValue(m.entry === 'plugin.js', 'Only bundled plugin.js is supported');
  keys(m.protocol, ['min', 'max']); negotiate(m.protocol, { min: 1, max: 1 });
  keys(m.capabilities, ['required', 'optional']);
  for (const list of [m.capabilities.required, m.capabilities.optional]) requireValue(Array.isArray(list) && list.length <= 64 && new Set(list).size === list.length && list.every(c => typeof c === 'string' && /^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)+$/.test(c)), 'Invalid capabilities');
  requireValue(Array.isArray(m.contributions) && m.contributions.length <= 64, 'Invalid contributions');
  const ids = new Set();
  for (const c of m.contributions) {
    keys(c, ['id', 'family', 'title', 'description', 'icon', 'schemaVersion', 'scopes', 'fields', 'handler', 'package','events','engine','extensions','kinds']);
    requireValue(families.includes(c.family) && c.id === namespacedId(m.id, c.id?.split(':')[1]) && !ids.has(c.id) && text(c.title), 'Invalid contribution'); ids.add(c.id);
    if (c.kinds !== undefined) requireValue(c.family === 'metadata.provider' && Array.isArray(c.kinds) && c.kinds.length > 0 && new Set(c.kinds).size === c.kinds.length && c.kinds.every(k => ['movie','television','video','musicTrack','musicAlbum','audiobook','ebook','comic'].includes(k)), 'Invalid provider kinds');
    if(c.events!==undefined) requireValue(c.family==='event.handler'&&Array.isArray(c.events)&&c.events.length>0&&c.events.length<=2&&new Set(c.events).size===c.events.length&&c.events.every(e=>['org.multiplexr:application.ready','org.multiplexr:library.changed'].includes(e)),'Invalid event subscription');
    if (c.family === 'settings.section') {
      requireValue(c.schemaVersion === 1 && text(c.description, 1000) && ['settings', 'book', 'music', 'video', 'palette', 'extension'].includes(c.icon), 'Invalid settings section');
      requireValue(Array.isArray(c.scopes) && c.scopes.length > 0 && new Set(c.scopes).size === c.scopes.length && c.scopes.every(s => scopes.includes(s)), 'Invalid scopes');
      requireValue(Array.isArray(c.fields) && c.fields.length > 0 && c.fields.length <= 64, 'Invalid settings fields');
      for (const field of c.fields) {
        validateField(field, m.id, c.scopes);
        requireValue(!ids.has(field.id), 'Duplicate ID'); ids.add(field.id);
      }
      for (const field of c.fields) for (const condition of [field.visibleWhen, field.enabledWhen].filter(Boolean)) {
        const dependency = c.fields.find(f => f.id === condition.field);
        requireValue(dependency && dependency !== field && dependency.type !== 'credential', 'Invalid condition dependency');
        validateSettingValue(dependency, condition.equals);
      }
      const visited = new Set(), visiting = new Set();
      function visit(field) {
        requireValue(!visiting.has(field.id), 'Cyclic settings condition');
        if (visited.has(field.id)) return;
        visiting.add(field.id);
        for (const condition of [field.visibleWhen, field.enabledWhen].filter(Boolean)) visit(c.fields.find(f => f.id === condition.field));
        visiting.delete(field.id); visited.add(field.id);
      }
      c.fields.forEach(visit);
    } else if(c.family === 'media.descriptor') {
      keys(c,['id','family','title','engine','extensions','kinds']);
      const engines={"reader.epub": ["epub"], "reader.text": ["txt"], "reader.pdf": ["pdf"], "reader.comic": ["cbz", "cbr"], "player.audio": ["mp3", "m4a", "m4b", "aac", "flac", "ogg", "oga", "opus", "wav"], "player.video": ["mp4", "mkv", "mov", "webm", "m4v", "avi", "ts", "m2ts", "3gp"]};
      requireValue(engines[c.engine] && Array.isArray(c.extensions) && c.extensions.length>0 && c.extensions.length<=16 && new Set(c.extensions).size===c.extensions.length && c.extensions.every(e=>engines[c.engine].includes(e)), 'Unsupported engine or codec');
    } else if (c.family === 'theme') {
      keys(c, ['id', 'family', 'title', 'package']);
      requireValue(c.package === 'theme.json', 'Theme package must be a data-only descriptor');
    } else {
      keys(c, ['id', 'family', 'title', 'handler', 'events', 'kinds']);
      requireValue(typeof c.handler === 'string' && /^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)+$/.test(c.handler), 'Handler required');
    }
  }
  return structuredClone(m);
}
