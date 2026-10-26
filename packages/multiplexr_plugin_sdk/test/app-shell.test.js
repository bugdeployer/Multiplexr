import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createContext, runInContext } from 'node:vm';
import { generateKeyPairSync } from 'node:crypto';
import * as AppShell from '../src/app-shell.js';
import { build } from '../bin/plugin.js';
import { signPackage, verifyPackage } from '../src/package.js';

test('neutral API exposes the same protocol plus contribution helpers', () => {
  assert.equal(AppShell.protocolVersion, 1);
  assert.equal(typeof AppShell.contribution, 'function');
  assert.equal(AppShell.namespacedId('org.example.notes', 'hello'), 'org.example.notes:hello');
});
test('independent Notes host builds, signs and invokes a plugin without Multiplexr app code', async () => {
  const scratch = await mkdtemp(join(tmpdir(), 'shell-notes-'));
  try {
    const artifact = await build(fileURLToPath(new URL('../examples/notes-tool/', import.meta.url)), join(scratch, 'notes.json'));
    const {privateKey} = generateKeyPairSync('ec', {namedCurve:'prime256v1'});
    const signed = signPackage(artifact, privateKey);
    verifyPackage(signed);
    // Trusted author fixture in a test VM only; never a production sandbox.
    const context = createContext({__hostCall: () => {throw Error('Unexpected host call');}});
    runInContext(artifact.code, context);
    const response = runInContext("multiplexrEntry({v:1,id:'notes-1',method:'notes.welcome',params:{scope:{scope:'app'}}})", context);
    assert.equal(response.result.kind, 'text');
    assert.equal(response.result.text, 'A reusable extension for a Notes host.');
  } finally {await rm(scratch, {recursive:true, force:true});}
});

test('author bundles are identical for Windows and Unix source line endings', async () => {
  const scratch = await mkdtemp(join(tmpdir(), 'shell-lines-'));
  try {
    const source = new URL('../examples/notes-tool/', import.meta.url);
    const outputs = [];
    for (const ending of ['\n', '\r\n']) {
      const folder = join(scratch, ending === '\n' ? 'unix' : 'windows');
      await mkdir(folder);
      for (const name of ['manifest.json', 'plugin.js']) {
        const text = (await readFile(new URL(name, source), 'utf8')).replace(/\r\n/g, '\n');
        await writeFile(join(folder, name), text.replace(/\n/g, ending));
      }
      outputs.push(await build(folder, join(folder, 'proof.json')));
    }
    assert.deepEqual(outputs[0], outputs[1]);
  } finally {await rm(scratch, {recursive:true, force:true});}
});
