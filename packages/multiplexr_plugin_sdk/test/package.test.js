import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { signPackage, verifyPackage, canonical } from '../src/package.js';
const keys=()=>generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const artifact=()=>({format:'multiplexr-plugin-proof-1',manifest:{id:'org.example.installed',name:'Installed tool',version:'1.0.0',entry:'plugin.js',protocol:{min:1,max:1},capabilities:{required:['runtime.ping'],optional:['catalog.read']},contributions:[{id:'org.example.installed:inspect',family:'library.tool',title:'Inspect',handler:'tool.inspect'}]},code:'globalThis.multiplexrEntry = function(input) { return {v:1,id:input.id,result:{ok:true}}; };',sha256:''});
function build() { const a=artifact();a.sha256=createHash('sha256').update(a.code).digest('hex');return a; }
test('signed package covers manifest, index, code and origins',()=>{
 const {privateKey}=keys();const signed=signPackage(build(),privateKey,['https://example.com']);
 assert.equal(verifyPackage(signed).manifest.id,'org.example.installed');
 for(const key of ['manifest','files','digests','networkOrigins']) {
   const tampered=structuredClone(signed),body=JSON.parse(Buffer.from(tampered.payload,'base64'));body[key]={changed:true};tampered.payload=Buffer.from(canonical(body)).toString('base64');assert.throws(()=>verifyPackage(tampered));
 }
});
test('publisher substitution, bad signatures and oversized packages are rejected',()=>{
 const signed=signPackage(build(),keys().privateKey);
 assert.throws(()=>verifyPackage({...signed,publicKey:signPackage(build(),keys().privateKey).publicKey}));
 assert.throws(()=>verifyPackage({...signed,signature:'AAAA'}));
 assert.throws(()=>verifyPackage({...signed,payload:'a'.repeat(600000)}));
});
test('only supported publisher curve and HTTPS origins can be signed',()=>{
 assert.throws(()=>signPackage(build(),generateKeyPairSync('ec',{namedCurve:'secp384r1'}).privateKey));
 for(const origin of ['http://example.com','https://example.com/path','https://user:pass@example.com','https://example.com:8443']) assert.throws(()=>signPackage(build(),keys().privateKey,[origin]));
});
test('standalone author fixture is a separately verifiable signed package',()=>{
 const bundle=JSON.parse(readFileSync(new URL('./fixtures/installed-v1.signed.json',import.meta.url)));
 assert.equal(verifyPackage(bundle).manifest.version,'1.0.0');
});

test('installed runtime fixture matches current independent SDK build', async()=>{
 const {build}=await import('../bin/plugin.js');
 const {mkdtemp,rm}=await import('node:fs/promises');
 const {tmpdir}=await import('node:os');
 const {join}=await import('node:path');
 const {fileURLToPath}=await import('node:url');
 const dir=await mkdtemp(join(tmpdir(),'multiplexr-signed-'));
 try {
   const artifact=await build(fileURLToPath(new URL('../examples/installed-inspector/',import.meta.url)),join(dir,'proof.json'));
   const bundle=JSON.parse(readFileSync(new URL('./fixtures/installed-inspector.signed.json',import.meta.url)));
   const body=verifyPackage(bundle);
   assert.equal(body.files['plugin.js'],artifact.code);
   assert.deepEqual(body.manifest,artifact.manifest);
 } finally { await rm(dir,{recursive:true,force:true}); }
});
