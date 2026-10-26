import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import Ajv from 'ajv/dist/2020.js';
import { validateManifest } from '../src/manifest.js';
const read = async path => JSON.parse(await readFile(new URL(path, import.meta.url)));
const ajv = new Ajv({ strict: false });
const manifestSchema = ajv.compile(await read('../schemas/manifest.schema.json'));
const protocolSchema = ajv.compile(await read('../schemas/protocol.schema.json'));
const manifest = await read('../examples/synthetic/manifest.json');
test('published manifest schema and semantic validator accept author fixture', () => {
  assert.equal(manifestSchema(manifest), true, JSON.stringify(manifestSchema.errors));
  validateManifest(manifest);
});
test('schemas reject unknown families, credentials defaults and ambiguous envelopes', () => {
  const unknown = structuredClone(manifest); unknown.contributions[0].family = 'native.codec';
  assert.equal(manifestSchema(unknown), false);
  const secret = structuredClone(manifest); secret.contributions[1].fields[2].default = 'secret';
  assert.equal(manifestSchema(secret), false);
  assert.equal(protocolSchema({ v: 1, id: 'a', result: {}, error: { code: 'plugin_error' } }), false);
  assert.equal(protocolSchema({ v: 1, id: 'a', method: 'metadata.search', params: { query: 'moon' } }), true);
  assert.equal(protocolSchema({ v: 2, id: 'a', result: {} }), false);
});

// The manifest validator and JSON schema must both reject invented decoders.
test('media descriptors only bind known host engines and codecs',()=>{
 const source=structuredClone(manifest);
 source.contributions=[{id:`${source.id}:format`,family:'media.descriptor',title:'Publication',engine:'reader.epub',extensions:['epub']}];
 assert.doesNotThrow(()=>validateManifest(source));
 source.contributions[0].extensions=['newdecoder'];
 assert.throws(()=>validateManifest(source));
});
