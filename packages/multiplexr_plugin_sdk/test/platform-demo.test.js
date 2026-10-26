import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createContext,runInContext} from 'node:vm';
import {build} from '../bin/plugin.js';
import {FakeHost} from '../src/fake-host.js';
import {validateContributionResult} from '../src/contributions.js';
test('independent platform sample runs each executable family with synthetic host data',async()=>{
 const scratch=await mkdtemp(join(tmpdir(),'mpx-platform-'));
 try {
  const artifact=await build(fileURLToPath(new URL('../examples/platform-demo/',import.meta.url)),join(scratch,'proof.json'));
  const context=createContext({});runInContext(artifact.code,context);
  const selection=[{id:'opaque-title',revision:'r1'}];
  const inputs={
   'metadata.provider':{query:'Example',kind:'ebook'},'artwork.provider':{title:'opaque-title',roles:['cover']},
   'source.provider':{root:'opaque-root'},'import.handler':{input:'opaque-input',mime:'text/plain',selection},
   'export.handler':{selection},'library.tool':{selection},'event.handler':{event:'org.multiplexr:library.changed',sequence:1,data:{}},
   'ui.action':{scope:{scope:'app'}},'ui.section':{scope:{scope:'title',collection:'opaque-collection',entity:'opaque-title'}},'ui.destination':{scope:{scope:'app'}},
   'session.hook':{session:'opaque-session',state:{kind:'time',milliseconds:100}},
  };
  const host={call:(method,params)=>{assert.equal(method,'imports.read');assert.equal(params.handle,'opaque-input');return {text:'Imported synthetic description',mime:'text/plain'};}};
  context.__hostCall=raw=>{const request=JSON.parse(raw);return JSON.stringify({v:1,id:request.id,result:host.call(request.method,request.params)});};
  for(const [family,params] of Object.entries(inputs)) {
   context.request=JSON.stringify({v:1,id:'sample',method:family,params});context.host=host;
   const response=JSON.parse(JSON.stringify(runInContext('multiplexrEntry(JSON.parse(request),host)',context)));
   assert.ok(response.result,family+' '+JSON.stringify(response));
   validateContributionResult(family,response.result,artifact.manifest.id);
   if(family==='import.handler')assert.equal(response.result.proposals[0].changes.description,'Imported synthetic description');
  }
  context.request=JSON.stringify({v:1,id:'rating',method:'library.rating',params:{selection}});
  context.__hostCall=raw=>{const request=JSON.parse(raw);assert.equal(request.method,'catalog.propose');assert.deepEqual(request.params.fields,{'org.example.platform:rating':5});return JSON.stringify({v:1,id:request.id,result:{proposal:'opaque-proposal',status:'awaitingConfirmation'}});};
  const rating=JSON.parse(JSON.stringify(runInContext('multiplexrEntry(JSON.parse(request))',context)));
  assert.deepEqual(rating.result,{proposals:[]});
  const fake=new FakeHost(artifact.manifest,{offeredCapabilities:artifact.manifest.capabilities.required.concat(artifact.manifest.capabilities.optional),inputs:{input:{text:'Read once',mime:'text/plain'}}});
  assert.equal(fake.call('imports.read',{handle:'input'}).text,'Read once');
  assert.throws(()=>fake.call('imports.read',{handle:'input'}));
  fake.disable();assert.throws(()=>fake.call('settings.register'));
 } finally {await rm(scratch,{recursive:true,force:true});}
});
