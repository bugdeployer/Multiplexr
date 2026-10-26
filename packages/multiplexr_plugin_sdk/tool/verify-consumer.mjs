// Pack/install into a clean consumer to catch exports, bin and packaging gaps.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, writeFile, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = await mkdtemp(join(tmpdir(), 'app-shell-consumer-'));
// Invoke npm's JS entrypoint directly to avoid Windows .cmd shell quoting.
const npm = process.env.npm_execpath;
if (!npm) throw Error('Run via npm run test:consumer');
const runNpm = (args, cwd) => execFileSync(process.execPath, [npm, ...args], {cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
try {
  const packed = JSON.parse(runNpm(['pack', '--json', '--pack-destination', scratch], root));
  await writeFile(join(scratch, 'package.json'), JSON.stringify({name: 'independent-notes-consumer', private: true, type: 'module'}));
  runNpm(['install', '--ignore-scripts', '--no-audit', '--no-fund', join(scratch, packed[0].filename)], scratch);
  const installed = join(scratch, 'node_modules', 'multiplexr_plugin_sdk');
  const manifest = JSON.parse(await readFile(join(installed, 'package.json'), 'utf8'));
  assert.equal(manifest.bin['app-shell-plugin'], './bin/plugin.js');
  await writeFile(join(scratch, 'verify.mjs'), `
import assert from 'node:assert/strict';
import * as AppShell from 'multiplexr_plugin_sdk/app-shell';
assert.equal(AppShell.protocolVersion, 1);
assert.equal(AppShell.namespacedId('org.example.notes', 'welcome'), 'org.example.notes:welcome');
assert.equal(typeof AppShell.contribution, 'function');
`);
  execFileSync(process.execPath, ['verify.mjs'], {cwd: scratch, stdio: 'pipe'});
  execFileSync(process.execPath, [join(installed, 'bin/plugin.js'), 'build', join(installed, 'examples/notes-tool'), join(scratch, 'notes.json')], {cwd: scratch, stdio: 'pipe'});
  assert.equal(JSON.parse(await readFile(join(scratch, 'notes.json'), 'utf8')).manifest.id, 'org.example.notes');
  console.log('Independent tarball consumer and Notes plugin build passed.');
} finally {
  await rm(scratch, {recursive: true, force: true});
}
