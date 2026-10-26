import { PluginError, envelope, negotiateCapabilities, validateJson, page } from './sdk.js';
import { validateManifest, validateSettingValue } from './manifest.js';

// Author-facing test double, never a production permission gateway.
export class FakeHost {
  #manifest; #fields = new Map(); #values = new Map(); #revision = 0;
  #events = []; #disabled = false; #collections; #titles;
  #grants; #inputs;
  constructor(manifest, { collections = [], titles = [], inputs = {}, offeredCapabilities = ['runtime.ping', 'settings.read', 'settings.write', 'catalog.read'] } = {}) {
    this.#manifest = validateManifest(manifest);
    this.#inputs=new Map(Object.entries(structuredClone(inputs)));
    this.#grants = new Set(negotiateCapabilities(manifest.capabilities.required, manifest.capabilities.optional, offeredCapabilities));
    this.#collections = new Set(collections);
    this.#titles = structuredClone(titles).map(title => ({...title, handle: title.id}));
    validateJson(this.#titles);
    for (const c of this.#manifest.contributions.filter(c => c.family === 'settings.section')) {
      for (const f of c.fields) this.#fields.set(f.id, f);
    }
  }
  disable() { this.#disabled = true; this.#events = []; }
  #address(address) {
    if (!address || !['app', 'collection', 'group', 'title'].includes(address.scope)) throw new PluginError('invalid_request');
    if (address.handle !== undefined) address = address.scope === 'collection' ? {scope: address.scope, collection: address.handle} : {scope: address.scope, collection: address.collection, entity: address.handle};
    if (Object.keys(address).some(key => !['scope', 'collection', 'entity'].includes(key))) throw new PluginError('invalid_request');
    if (address.scope === 'app') {
      if (address.collection !== undefined || address.entity !== undefined) throw new PluginError('invalid_request');
    } else {
      if (!this.#collections.has(address.collection)) throw new PluginError('permission_denied');
      if (address.scope === 'collection' ? address.entity !== undefined : typeof address.entity !== 'string' || !address.entity.length) throw new PluginError('invalid_request');
    }
    return JSON.stringify([address.scope, address.collection ?? '', address.entity ?? '']);
  }
  #field(id) {
    if (typeof id !== 'string' || !id.startsWith(`${this.#manifest.id}:`)) throw new PluginError('permission_denied');
    const field = this.#fields.get(id);
    if (!field) throw new PluginError('not_found');
    if (field.type === 'credential') throw new PluginError('permission_denied');
    return field;
  }
  call(method, params = {}) {
    if (this.#disabled) throw new PluginError('permission_denied');
    validateJson(params);
    const capability = {
      'runtime.ping': 'runtime.ping', 'settings.register': 'settings.read',
      'settings.effective': 'settings.read', 'settings.changes': 'settings.read',
      'settings.propose': 'settings.write', 'settings.reset': 'settings.write',
      'imports.read':'import.parse', 'catalog.titles': 'catalog.read', 'catalog.title':'catalog.read', 'catalog.fields':'catalog.read',
    }[method];
    if (capability && !this.#grants.has(capability)) throw new PluginError('permission_denied');
    if(method==='imports.read') { const input=this.#inputs.get(params.handle);if(!input)throw new PluginError('not_found');this.#inputs.delete(params.handle);return structuredClone(input); }
    if (method === 'runtime.ping') return { protocol: 1, runtime: 'fake' };
    if (method === 'settings.register') return { sections: this.#manifest.contributions.filter(c => c.family === 'settings.section').map(c => c.id) };
    if (method === 'settings.effective') {
      const field = this.#field(params.id);
      if (!Array.isArray(params.lineage) || !params.lineage.length || params.lineage.length > 4) throw new PluginError('invalid_request');
      let previous = -1, collection, value = field.default, source = null;
      for (const address of params.lineage) {
        const key = this.#address(address);
        const index = ['app', 'collection', 'group', 'title'].indexOf(address.scope);
        if (index <= previous || address.collection && collection && address.collection !== collection) throw new PluginError('invalid_request');
        previous = index; collection = address.collection ?? collection;
        if (field.scopes.includes(address.scope) && this.#values.has(`${key}/${params.id}`)) {
          value = this.#values.get(`${key}/${params.id}`); source = address;
        }
      }
      return structuredClone({ value, source, revision: this.#revision });
    }
    if (method === 'settings.propose' || method === 'settings.reset') {
      const field = this.#field(params.id), address = this.#address(params.address);
      if (!field.scopes.includes(params.address.scope)) throw new PluginError('permission_denied');
      if (params.expectedRevision !== this.#revision) throw new PluginError('conflict');
      if (method === 'settings.propose') validateSettingValue(field, params.value);
      const key = `${address}/${params.id}`;
      if (method === 'settings.reset') this.#values.delete(key);
      else this.#values.set(key, structuredClone(params.value));
      this.#revision++;
      this.#events.push({ id: params.id, address: structuredClone(params.address), revision: this.#revision });
      // A bounded, lossy notification stream. Consumers re-query effective values.
      if (this.#events.length > 32) this.#events.shift();
      return { revision: this.#revision };
    }
    if (method === 'settings.changes') {
      if (!Number.isInteger(params.afterRevision) || params.afterRevision < 0 || params.afterRevision > this.#revision) throw new PluginError('invalid_request');
      return structuredClone({ events: this.#events.filter(e => e.revision > params.afterRevision),
        resyncRequired: params.afterRevision < (this.#events[0]?.revision ?? this.#revision + 1) - 1, revision: this.#revision });
    }
    if (method === 'catalog.title' || method === 'catalog.fields') {
      const title=this.#titles.find(t=>t.id===params.handle);
      if(!title || !this.#collections.has(title.collection)) throw new PluginError('permission_denied');
      if(method==='catalog.title') return structuredClone(title);
      return Object.fromEntries(Object.entries(title.fields??{}).filter(([id])=>id.startsWith(`${this.#manifest.id}:`)));
    }
    if (method === 'catalog.titles') {
      if (!this.#collections.has(params.collection ?? params.handle)) throw new PluginError('permission_denied');
      const limit = params.limit ?? 50, offset = params.cursor === undefined || params.cursor === null ? 0 : Number(params.cursor);
      if (!Number.isInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset < 0) throw new PluginError('invalid_request');
      const rows = this.#titles.filter(t => t.collection === (params.collection ?? params.handle));
      return page(structuredClone(rows.slice(offset, offset + limit)), offset + limit < rows.length ? String(offset + limit) : null);
    }
    // No raw settings, file handles, native engines, locks or mutations.
    throw new PluginError('unsupported_capability');
  }
  transport = text => {
    let id = null;
    try {
      if (typeof text !== 'string' || Buffer.byteLength(text) > 65536) throw new PluginError('message_too_large');
      const q = JSON.parse(text);
      if (q.v !== 1) throw new PluginError('version_mismatch');
      envelope(q); id = q.id;
      return JSON.stringify(envelope({ v: 1, id, result: this.call(q.method, q.params) }, true));
    } catch (error) { return JSON.stringify({ v: 1, id, error: { code: error instanceof PluginError ? error.code : 'invalid_request' } }); }
  };
}
