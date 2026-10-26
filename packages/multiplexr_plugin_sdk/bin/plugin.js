#!/usr/bin/env node
import { signPackage } from '../src/package.js';
import { readFile, writeFile, mkdir, lstat } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { Script } from 'node:vm';
import { validateManifest } from '../src/manifest.js';

export async function build(folder, output) {
  async function boundedFile(name, maximum) {
    const path = resolve(folder, name), info = await lstat(path);
    if (!info.isFile() || info.isSymbolicLink() || info.size > maximum) throw Error('Invalid or oversized source file');
    return (await readFile(path, 'utf8')).replace(/\r\n/g, '\n');
  }
  const manifestText = await boundedFile('manifest.json', 65536);
  if (Buffer.byteLength(manifestText) > 65536) throw Error('Manifest too large');
  const manifest = validateManifest(JSON.parse(manifestText));
  if (manifest.contributions.some(c => c.family === 'theme')) throw Error('unsupported_capability: use standalone data-only theme JSON; executable contributions cannot contain themes');
  const sdk = (await readFile(new URL('../src/sdk.js', import.meta.url), 'utf8')).replace(/\r\n/g, '\n').replace(/^export /gm, '');
  const contracts = (await readFile(new URL('../src/contributions.js', import.meta.url), 'utf8'))
    .replace(/\r\n/g, '\n')
    .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
  const author = await boundedFile(manifest.entry, 65536);
  const code = `const Multiplexr = (() => {\n${sdk}\n${contracts}\nreturn Object.freeze({definePlugin, contribution, request, page, namespacedId, PluginError, Cancellation, negotiate, negotiateCapabilities, httpJson});\n})();\nconst AppShell = Multiplexr;\n${author}`;
  if (Buffer.byteLength(code) > 65536) throw Error('Bundled program exceeds 64 KiB');
  // Parse without running author code. Imports are deliberately not resolved.
  new Script(code, { filename: 'plugin.js' });
  const artifact = { format: 'multiplexr-plugin-proof-1', manifest, code,
    sha256: createHash('sha256').update(code).digest('hex') };
  await mkdir(dirname(resolve(output)), { recursive: true });
  await writeFile(output, JSON.stringify(artifact) + '\n', { flag: 'wx' });
  return artifact;
}
export async function validate(file) {
  const info = await lstat(file);
  if (!info.isFile() || info.size > 160000) throw Error('Invalid or oversized artifact');
  const bytes = await readFile(file);
  if (bytes.length > 160000) throw Error('Artifact too large');
  const artifact = JSON.parse(bytes);
  validateManifest(artifact.manifest);
  if (artifact.manifest.contributions.some(c => c.family === 'theme')) throw Error('unsupported_capability: executable artifacts cannot contain themes');
  if (Object.keys(artifact).some(key => !['format', 'manifest', 'code', 'sha256'].includes(key))) throw Error('Unknown artifact field');
  if (artifact.format !== 'multiplexr-plugin-proof-1' || typeof artifact.code !== 'string' || Buffer.byteLength(artifact.code) > 65536 ||
      artifact.sha256 !== createHash('sha256').update(artifact.code).digest('hex')) throw Error('Invalid artifact');
  new Script(artifact.code);
  return artifact;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, input, output] = process.argv.slice(2);
    if (command === 'build' && input && output) await build(input, output);
    else if (command === 'validate' && input) await validate(input);
    else if (command === 'sign' && input && output && process.argv[5]) {
      const artifact = await validate(input);
      const key = await readFile(process.argv[5], 'utf8');
      const origins = process.argv.slice(6);
      await writeFile(output, JSON.stringify(signPackage(artifact, key, origins)) + '\n', {flag: 'wx'});
    }
    else throw Error('Usage: multiplexr-plugin build <folder> <new-output.json> | validate <artifact.json> | sign <artifact.json> <new-output.mpx.json> <private-key.pem> [https-origin ...]');
    console.log('Package operation completed. Installation still requires host review and grants.');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
