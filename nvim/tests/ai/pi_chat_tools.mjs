// Run with Node 24+: node nvim/tests/ai/pi_chat_tools.mjs /path/to/pi-coding-agent
import assert from 'node:assert/strict';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const temp = realpathSync(mkdtempSync(join(tmpdir(), 'pi-chat-fixture-')));
try {
  const workspace = join(temp, 'repo');
  mkdirSync(workspace);
  process.env.NVIM_AI_PI_ROOT = workspace;
  // Copy the trusted extension into a temporary module tree with Pi's TypeBox dependency.
  const packageRoot = resolve(process.argv[2]);
  symlinkSync(join(packageRoot, 'node_modules'), join(temp, 'node_modules'), 'dir');
  const extension = join(temp, 'tools.mts');
  cpSync(new URL('../../scripts/ai/pi-chat-tools.ts', import.meta.url), extension);
  const { default: register } = await import(pathToFileURL(extension));
  const tools = new Map();
  register({ registerTool(tool) { tools.set(tool.name, tool); } });

  const run = (tool, args, decide = () => { throw new Error('Unexpected approval'); }) =>
    tools.get(`workspace_${tool}`).execute('fixture', args, undefined, undefined, {
      ui: { async confirm(title, message) {
        assert.equal(title, tool === 'run' ? 'Run Pi workspace command' : 'Review Pi workspace change');
        return decide(JSON.parse(message));
      } },
    });
  const text = result => result.content[0].text;
  const file = join(workspace, 'file.txt');
  const original = 'one\nleave this\nthree\n';
  writeFileSync(file, original);
  writeFileSync(join(workspace, '.env'), 'leave this');
  writeFileSync(join(temp, 'outside.txt'), 'leave this');
  symlinkSync(join(temp, 'outside.txt'), join(workspace, 'link'));
  assert.equal(text(await run('search', { path: '.', mode: 'text', query: 'leave this' })), 'file.txt:2: leave this');
  assert.equal(text(await run('search', { path: '.', mode: 'name', query: 'file' })), 'file.txt');
  await assert.rejects(run('read', { path: 'link' }));
  await assert.rejects(run('read', { path: '../outside.txt' }));
  await assert.rejects(run('read', { path: '.env' }));

  const edit = { path: 'file.txt', edits: [{ oldText: 'three', newText: 'THREE' }, { oldText: 'one', newText: 'ONE' }] };
  const updated = 'ONE\nleave this\nTHREE\n';
  const reviewEdit = (yes) => run('edit', edit, proposal => {
    assert.deepEqual(proposal, { operation: 'edit', path: file, before: original, after: updated });
    assert.equal(readFileSync(file, 'utf8'), original);
    return yes;
  });
  await reviewEdit(false);
  assert.equal(readFileSync(file, 'utf8'), original);
  await reviewEdit(true);
  assert.equal(readFileSync(file, 'utf8'), updated);
  await assert.rejects(run('edit', { ...edit, edits: [{ oldText: 'ONE', newText: '' }, { oldText: 'NE', newText: '' }] }), /overlap/);
  await run('mkdir', { path: 'sub' }, p => p.operation === 'mkdir');
  await run('move', { path: 'file.txt', destination: 'sub/new.txt' }, p => p.operation === 'move');
  const moved = join(workspace, 'sub/new.txt');
  assert.equal(readFileSync(moved, 'utf8'), updated);
  assert.throws(() => readFileSync(file));
  await run('create', { path: 'file.txt', text: '' }, p => p.operation === 'create');
  assert.equal(readFileSync(file, 'utf8'), '');
  await assert.rejects(run('move', { path: 'sub/new.txt', destination: 'file.txt' }));
  await assert.rejects(run('delete', { path: 'sub/new.txt' }, (p) => {
    assert.equal(p.operation, 'delete');
    writeFileSync(moved, 'updated by someone else');
    return true;
  }), /changed during review/);
  assert.equal(readFileSync(moved, 'utf8'), 'updated by someone else');
  await run('delete', { path: 'sub/new.txt' }, p => p.operation === 'delete' && p.before === 'updated by someone else');
  assert.throws(() => readFileSync(moved));
  console.log('Pi Chat workspace tools: search, multi-edit, move, mkdir, delete, reject, and stale-file guards passed');

  if (tools.has('workspace_run')) {
    const home = join(temp, 'home');
    const managed = join(home, '.local/share/uv/python');
    const runtime = join(managed, 'cpython-3.12.12-macos-aarch64-none');
    const other = join(managed, 'cpython-3.13.1-macos-aarch64-none');
    const bin = join(workspace, '.venv/bin');
    mkdirSync(join(runtime, 'bin'), { recursive: true });
    mkdirSync(other, { recursive: true });
    mkdirSync(bin, { recursive: true });
    const python = join(runtime, 'bin/python3.12');
    writeFileSync(python, '#!/bin/sh\necho runtime-ok\n', { mode: 0o700 });
    writeFileSync(join(runtime, 'library'), 'runtime-library\n');
    writeFileSync(join(other, 'library'), 'wrong-runtime\n');
    symlinkSync(python, join(bin, 'python'));
    process.env.HOME = home;
    const command = (command) => run('run', { command }, () => true).then(text);
    assert.match(await command('.venv/bin/python'), /^Exit 0\nruntime-ok\n$/);
    assert.match(await command(`cat "${runtime}/library"`), /^Exit 0\nruntime-library\n$/);
    assert.match(await command(`cat "${other}/library"`), /^Exit [1-9]/);
    assert.match(await command(`echo write > "${runtime}/library"`), /^Exit [1-9]/);
    rmSync(join(bin, 'python'));
    symlinkSync(join(temp, 'outside.txt'), join(bin, 'python'));
    assert.match(await command(`cat "${runtime}/library"`), /^Exit [1-9]/);
    console.log('Pi Chat sandbox: only the workspace’s selected uv Python runtime is readable, never writable');
  }
} finally {
  rmSync(temp, { recursive: true, force: true });
}
