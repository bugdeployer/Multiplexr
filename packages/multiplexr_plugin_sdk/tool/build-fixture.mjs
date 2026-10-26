// Test publisher keys are ephemeral and never written to disk.
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {build} from '../bin/plugin.js';
import {signPackage} from '../src/package.js';

const scratch = await mkdtemp(join(tmpdir(), 'app-shell-fixture-'));
try {
  const artifact = await build(fileURLToPath(new URL('../examples/installed-inspector/', import.meta.url)), join(scratch, 'proof.json'));
  const bundle = signPackage(artifact, generateKeyPairSync('ec', {namedCurve: 'prime256v1'}).privateKey);
  await writeFile(new URL('../test/fixtures/installed-inspector.signed.json', import.meta.url), JSON.stringify(bundle, null, 2) + '\n');
} finally {
  await rm(scratch, {recursive: true, force: true});
}
