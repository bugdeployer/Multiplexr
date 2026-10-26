import { createHash, createPublicKey, sign, verify } from 'node:crypto';
import { validateManifest } from './manifest.js';
export const packageFormat = 'multiplexr-plugin-1';
export function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
}
export function signPackage(artifact, privateKey, origins = []) {
  const manifest = validateManifest(artifact.manifest);
  if (artifact.format !== 'multiplexr-plugin-proof-1' || typeof artifact.code !== 'string' || Buffer.byteLength(artifact.code) > 65536) throw Error('Invalid build artifact');
  const hash = createHash('sha256').update(artifact.code).digest('hex');
  if (hash !== artifact.sha256) throw Error('Digest mismatch');
  const key = createPublicKey(privateKey);
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails.namedCurve !== 'prime256v1') throw Error('P-256 publisher key required');
  const networkOrigins = [...new Set(origins)].sort();
  for (const origin of networkOrigins) {
    const url = new URL(origin);
    if (url.protocol !== 'https:' || url.origin !== origin || url.username || url.password || url.port && url.port !== '443') throw Error('HTTPS origins required');
  }
  const payload = Buffer.from(canonical({manifest, files: {'plugin.js': artifact.code}, digests: {'plugin.js': hash}, networkOrigins, host: {min: 1, max: 1}}));
  return {format: packageFormat, payload: payload.toString('base64'), publicKey: key.export({type: 'spki', format: 'der'}).toString('base64'), signature: sign('sha256', payload, privateKey).toString('base64')};
}
export function verifyPackage(bundle) {
  if (bundle.format !== packageFormat || Object.keys(bundle).sort().join(',') !== 'format,payload,publicKey,signature' || Buffer.byteLength(JSON.stringify(bundle)) > 524288) throw Error('Invalid signed package');
  const payload = Buffer.from(bundle.payload, 'base64'), key = createPublicKey({key: Buffer.from(bundle.publicKey, 'base64'), type: 'spki', format: 'der'});
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails.namedCurve !== 'prime256v1' || !verify('sha256', payload, key, Buffer.from(bundle.signature, 'base64'))) throw Error('Invalid signature');
  const body = JSON.parse(payload);
  if (canonical(body) !== payload.toString('utf8')) throw Error('Noncanonical payload');
  validateManifest(body.manifest);
  if (Object.keys(body).sort().join(',') !== 'digests,files,host,manifest,networkOrigins' || !body.host || Object.keys(body.host).sort().join(',') !== 'max,min' || !Number.isInteger(body.host.min) || !Number.isInteger(body.host.max) || body.host.min > 1 || body.host.min < 1 || body.host.max < 1) throw Error('Incompatible host');
  if (!Array.isArray(body.networkOrigins) || body.networkOrigins.length > 32 || new Set(body.networkOrigins).size !== body.networkOrigins.length) throw Error('Invalid origins');
  for (const origin of body.networkOrigins) {
    const url = new URL(origin);
    if (url.protocol !== 'https:' || url.origin !== origin || url.username || url.password || url.port && url.port !== '443') throw Error('HTTPS origins required');
  }
  if (Object.keys(body.files).join(',') !== 'plugin.js' || Object.keys(body.digests).join(',') !== 'plugin.js' || typeof body.files['plugin.js'] !== 'string' || Buffer.byteLength(body.files['plugin.js']) > 65536 || createHash('sha256').update(body.files['plugin.js']).digest('hex') !== body.digests['plugin.js']) throw Error('Invalid file index');
  return body;
}
