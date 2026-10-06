import assert from 'node:assert/strict';
import { mkdtemp, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import { appendPrompt, main, mention, parseInvocation, pickServer, promptText } from '../assets/inject.mjs';

test('retains the legacy helper invocation', () => {
	assert.deepEqual(parseInvocation(['my-dsh', 'work-tui', '/tmp/one']), {
		command: ['my-dsh', '--profile', 'work-tui'], selected: ['/tmp/one'],
	});
});

test('keeps command arguments separate from selected files', () => {
	assert.deepEqual(parseInvocation([
		'--command', '4', '/bin/my dsh', '--profile', 'work-tui', '--debug', '/tmp/one', '/tmp/two files',
	]), {
		command: ['/bin/my dsh', '--profile', 'work-tui', '--debug'], selected: ['/tmp/one', '/tmp/two files'],
	});
});

test('rejects malformed invocations before launching', async () => {
	for (const argv of [[], ['dsh'], ['dsh', 'work'], ['--command', '0', 'dsh', '/tmp/file'],
		['--command', '-1', 'dsh', '/tmp/file'], ['--command', '1.5', 'dsh', '/tmp/file'],
		['--command', 'oops', 'dsh', '/tmp/file'], ['--command', '4', 'dsh', '/tmp/file'],
		['--command', '1', '', '/tmp/file'], ['--command', '1', 'dsh']]) {
		assert.equal(parseInvocation(argv), undefined);
		assert.equal(await main(argv), 2);
	}
});

test('launches custom arguments through a linked helper and preserves the child exit code', async (context) => {
	if (process.platform === 'win32') {
		context.skip('Symbolic link fixture requires Unix');
		return;
	}
	const dir = await mkdtemp(join(tmpdir(), 'dsh-tui-yazi-launch-'));
	try {
		const helper = join(dir, 'linked-helper.mjs');
		const agent = join(dir, 'agent with spaces.mjs');
		await symlink(fileURLToPath(new URL('../assets/inject.mjs', import.meta.url)), helper);
		await writeFile(agent, `console.log(JSON.stringify({ cwd: process.cwd(), args: process.argv.slice(2) })); process.exit(23);`);
		const child = spawn(process.execPath, [helper, '--command', '5', process.execPath, agent,
			'--profile', 'work-tui', '$(not-a-shell); space', '/tmp/selected file'], { cwd: dir });
		let stdout = '';
		let stderr = '';
		child.stdout.setEncoding('utf8').on('data', (chunk) => { stdout += chunk; });
		child.stderr.setEncoding('utf8').on('data', (chunk) => { stderr += chunk; });
		const code = await new Promise((done, reject) => {
			child.once('error', reject);
			child.once('close', done);
		});
		assert.equal(code, 23, stderr);
		assert.deepEqual(JSON.parse(stdout), {
			cwd: await realpath(dir), args: ['--profile', 'work-tui', '$(not-a-shell); space'],
		});
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test('formats selected paths as DSH mentions', () => {
	assert.equal(mention('/tmp/plain.txt'), '@/tmp/plain.txt');
	assert.equal(mention('/tmp/with space.txt'), '@"/tmp/with space.txt"');
	assert.equal(
		promptText(['/tmp/one.txt', '/tmp/two files.txt']),
		'@/tmp/one.txt @"/tmp/two files.txt" ',
	);
});

test('prefers the DSH process that was just launched', () => {
	const records = [
		{ pid: 10, cwd: '/work', startedAt: 100, socketPath: '/tmp/old.sock' },
		{ pid: 20, cwd: '/other', startedAt: 200, socketPath: '/tmp/exact.sock' },
	];
	assert.equal(pickServer(records, 20, '/work', 150).socketPath, '/tmp/exact.sock');
});

test('ignores a stale discovery record with a reused process ID', () => {
	const records = [
		{ pid: 20, cwd: '/other', startedAt: 100, socketPath: '/tmp/stale-exact.sock' },
		{ pid: 21, cwd: '/work', startedAt: 200, socketPath: '/tmp/current.sock' },
	];
	assert.equal(pickServer(records, 20, '/work', 150).socketPath, '/tmp/current.sock');
});

test('falls back to the newest matching workspace session', () => {
	const records = [
		{ pid: 10, cwd: '/work', startedAt: 200, socketPath: '/tmp/older.sock' },
		{ pid: 11, cwd: '/work', startedAt: 300, socketPath: '/tmp/newer.sock' },
		{ pid: 12, cwd: '/work', startedAt: 100, socketPath: '/tmp/stale.sock' },
	];
	assert.equal(pickServer(records, 99, '/work', 150).socketPath, '/tmp/newer.sock');
});

test('appends a draft without submitting it', async (context) => {
	if (process.platform === 'win32') {
		context.skip('Unix socket fixture');
		return;
	}

	const dir = await mkdtemp(join(tmpdir(), 'dsh-tui-yazi-'));
	const socketPath = join(dir, 'inject.sock');
	const server = createServer();
	const received = new Promise((done) => {
		server.on('connection', (socket) => {
			socket.setEncoding('utf8');
			socket.once('data', done);
		});
	});

	await new Promise((done, reject) => {
		server.once('error', reject);
		server.listen(socketPath, done);
	});
	try {
		await appendPrompt(socketPath, '@/tmp/example.txt ');
		assert.deepEqual(JSON.parse((await received).trim()), {
			type: 'prompt.append',
			text: '@/tmp/example.txt ',
		});
	} finally {
		await new Promise((done) => server.close(done));
		await rm(dir, { recursive: true, force: true });
	}
});
