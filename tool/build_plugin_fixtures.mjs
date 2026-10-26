// Test assets only. Private signing keys live in memory for this invocation.
import {build} from '../packages/multiplexr_plugin_sdk/bin/plugin.js';
import {signPackage,verifyPackage} from '../packages/multiplexr_plugin_sdk/src/package.js';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
const scratch=await mkdtemp(join(tmpdir(),'multiplexr-fixtures-'));
const assets=new URL('../android/app/src/androidTest/assets/',import.meta.url);
try {
 for(const [example,name,signed] of [['synthetic','synthetic.plugin.json',false],['installed-inspector','installed-signed.plugin.json',true],['platform-demo','platform-demo.plugin.json',true]]) {
  const artifact=await build(fileURLToPath(new URL(`../packages/multiplexr_plugin_sdk/examples/${example}/`,import.meta.url)),join(scratch,example+'.json'));
  // Preserve the pinned upstream fixture; do not modify vendored SDK sources.
  const value=example==='installed-inspector'
   ? JSON.parse(await readFile(new URL('../packages/multiplexr_plugin_sdk/test/fixtures/installed-inspector.signed.json',import.meta.url),'utf8'))
   : signed ? signPackage(artifact,generateKeyPairSync('ec',{namedCurve:'prime256v1'}).privateKey) : artifact;
  if(example==='installed-inspector' && verifyPackage(value).files['plugin.js']!==artifact.code) throw Error('Upstream fixture is stale');
  await writeFile(new URL(name,assets),JSON.stringify(value,null,2)+'\n');
 }
} finally {await rm(scratch,{recursive:true,force:true});}
