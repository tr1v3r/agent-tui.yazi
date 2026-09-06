import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import test from 'node:test';

import { appendPrompt, mention, pickServer, promptText } from '../inject.mjs';

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
