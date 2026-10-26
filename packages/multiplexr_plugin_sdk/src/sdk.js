// This file has no host imports and runs in both QuickJS and the author test host.
export const protocolVersion = 1;
export const families = Object.freeze([
  'metadata.provider', 'artwork.provider', 'source.provider', 'import.handler',
  'export.handler', 'library.tool', 'event.handler', 'ui.action', 'ui.section',
  'ui.destination', 'settings.section', 'theme', 'session.hook', 'media.descriptor',
]);
export const errorCodes = Object.freeze([
  'invalid_request', 'invalid_response', 'version_mismatch', 'unsupported_capability',
  'permission_denied', 'not_found', 'conflict', 'cancelled', 'deadline_exceeded',
  'resource_limit', 'message_too_large', 'busy', 'plugin_error', 'runtime_failure',
]);
export class PluginError extends Error {
  constructor(code, message = code) {
    super(message);
    this.code = errorCodes.includes(code) ? code : 'plugin_error';
  }
}
export function requireValue(condition, message) {
  if (!condition) throw new PluginError('invalid_request', message);
}
export function namespacedId(owner, local) {
  requireValue(typeof owner === 'string' && /^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$/.test(owner) && owner.length <= 80, 'Invalid plugin namespace');
  requireValue(typeof local === 'string' && /^[a-z][a-zA-Z0-9_.-]{0,79}$/.test(local), 'Invalid local ID');
  return `${owner}:${local}`;
}
export function negotiate(requested, offered) {
  requireValue(requested && offered && Number.isInteger(requested.min) && Number.isInteger(requested.max)
    && Number.isInteger(offered.min) && Number.isInteger(offered.max)
    && requested.min >= 1 && requested.max >= requested.min && offered.min >= 1 && offered.max >= offered.min, 'Invalid version range');
  const v = Math.min(requested.max, offered.max);
  if (v < Math.max(requested.min, offered.min)) throw new PluginError('version_mismatch');
  return v;
}
export function negotiateCapabilities(required, optional, offered) {
  requireValue([required, optional, offered].every(a => Array.isArray(a) && a.length <= 64 && a.every(v => typeof v === 'string')), 'Invalid capabilities');
  if (required.some(c => !offered.includes(c))) throw new PluginError('unsupported_capability');
  return Object.freeze([...new Set([...required, ...optional.filter(c => offered.includes(c))])]);
}
export class Cancellation {
  #cancelled = false;
  cancel() { this.#cancelled = true; }
  get cancelled() { return this.#cancelled; }
  check() { if (this.cancelled) throw new PluginError('cancelled'); }
}
export function page(items, nextCursor = null) {
  requireValue(Array.isArray(items) && items.length <= 100 && (nextCursor === null || typeof nextCursor === 'string' && nextCursor.length <= 256), 'Invalid page');
  return Object.freeze({ items: Object.freeze([...items]), nextCursor });
}
export function validateJson(value, depth = 0) {
  requireValue(depth <= 24, 'JSON nesting limit');
  if (value === null || typeof value === 'boolean') return;
  if (typeof value === 'number') { requireValue(Number.isFinite(value), 'Finite number required'); return; }
  if (typeof value === 'string') { requireValue(value.length <= 32768, 'String limit'); return; }
  requireValue(typeof value === 'object' && (Array.isArray(value) || Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null), 'JSON value required');
  const entries = Object.entries(value);
  requireValue(entries.length <= 1024, 'Container limit');
  for (const [key, item] of entries) {
    requireValue(key !== '__proto__' && key !== 'prototype' && key !== 'constructor', 'Reserved key');
    validateJson(item, depth + 1);
  }
}
export function byteLength(value) {
  let bytes = 0;
  for (const character of value) {
    const cp = character.codePointAt(0);
    bytes += cp <= 0x7f ? 1 : cp <= 0x7ff ? 2 : cp <= 0xffff ? 3 : 4;
  }
  return bytes;
}
export function envelope(input, response = false) {
  validateJson(input);
  requireValue(input && typeof input === 'object' && !Array.isArray(input), 'Envelope required');
  if (input.v !== protocolVersion) throw new PluginError('version_mismatch');
  const fields = response ? ['v', 'id', 'result', 'error'] : ['v', 'id', 'method', 'params'];
  requireValue(Object.keys(input).every(key => fields.includes(key)), 'Unknown envelope field');
  if (response) {
    requireValue(Object.hasOwn(input, 'result') !== Object.hasOwn(input, 'error'), 'Ambiguous response');
    if (Object.hasOwn(input, 'error')) {
      requireValue(input.error && typeof input.error === 'object' &&
        Object.keys(input.error).length === 1 && errorCodes.includes(input.error.code), 'Invalid error');
    }
    requireValue(input.id === null && Object.hasOwn(input, 'error') ||
      typeof input.id === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(input.id), 'Invalid response ID');
  } else {
    requireValue(Object.hasOwn(input, 'params'), 'Missing params');
    request(input.id, input.method, input.params);
  }
  if (byteLength(JSON.stringify(input)) > 65536) throw new PluginError('message_too_large');
  return input;
}
export function request(id, method, params = {}) {
  requireValue(typeof id === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(id), 'Invalid request ID');
  requireValue(typeof method === 'string' && /^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)+$/.test(method) && method.length <= 100, 'Invalid method');
  validateJson(params);
  return { v: protocolVersion, id, method, params };
}
export function createHost(transport) {
  let sequence = 0;
  return Object.freeze({ call(method, params = {}, cancellation = new Cancellation()) {
    cancellation.check();
    const outgoing = request(`h${++sequence}`, method, params);
    envelope(outgoing);
    const raw = transport(JSON.stringify(outgoing));
    if (typeof raw !== 'string' || byteLength(raw) > 65536) throw new PluginError('invalid_response');
    let reply;
    try { reply = envelope(JSON.parse(raw), true); }
    catch (_) { throw new PluginError('invalid_response'); }
    cancellation.check();
    if (reply.v !== 1 || reply.id !== outgoing.id || Object.hasOwn(reply, 'result') === Object.hasOwn(reply, 'error')) throw new PluginError('invalid_response');
    if (reply.error) throw new PluginError(reply.error.code);
    requireValue(Object.hasOwn(reply, 'result'), 'Missing response');
    return reply.result;
  } });
}
export function definePlugin(handlers) {
  return function dispatch(input) {
    let id = null;
    try {
      envelope(input);
      id = input.id;
      if (!Object.hasOwn(handlers, input.method)) throw new PluginError('unsupported_capability');
      const result = handlers[input.method](input.params, createHost(globalThis.__hostCall));
      validateJson(result);
      return envelope({ v: 1, id, result }, true);
    } catch (error) {
      return { v: 1, id, error: { code: error instanceof PluginError ? error.code : 'plugin_error' } };
    }
  };
}
