import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import { createConnection } from 'node:net';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const mention = (file) => {
	const absolute = resolve(file);
	if (!/\s/.test(absolute)) return `@${absolute}`;
	if (!absolute.includes('"')) return `@"${absolute}"`;
	return absolute;
};

export const promptText = (selected) => `${selected.map(mention).join(' ')} `;

export const pickServer = (records, targetPid, cwd, launchedAt) => {
	if (!Array.isArray(records)) return undefined;

	const exact = records.find(
		(record) => record?.pid === targetPid && record?.startedAt >= launchedAt,
	);
	if (exact) return exact;

	return records
		.filter((record) => record?.cwd === cwd && record?.startedAt >= launchedAt)
		.sort((left, right) => right.startedAt - left.startedAt)[0];
};

export const appendPrompt = (socketPath, text, timeout = 500) => new Promise((done, reject) => {
	const socket = createConnection(socketPath);
	const timer = setTimeout(() => {
		socket.destroy();
		reject(new Error('Timed out connecting to dsh-tui'));
	}, timeout);

	socket.once('error', (error) => {
		clearTimeout(timer);
		reject(error);
	});
	socket.once('connect', () => {
		socket.end(`${JSON.stringify({ type: 'prompt.append', text })}\n`, () => {
			clearTimeout(timer);
			done();
		});
	});
});

const delay = (milliseconds) => new Promise((done) => setTimeout(done, milliseconds));

export async function main(argv = process.argv.slice(2)) {
	const [dshBin, profile, ...selected] = argv;
	if (!dshBin || !profile || selected.length === 0) return 2;

	const launchedAt = Date.now();
	const cwd = process.cwd();
	const serversFile = resolve(homedir(), '.dsh-tui/inject/servers.json');
	const deadline = launchedAt + 15_000;
	const dsh = spawn(dshBin, ['--profile', profile], { stdio: 'inherit' });
	const targetPid = dsh.pid;
	let serverReadyAt;

	const exitCode = new Promise((done) => {
		dsh.once('error', () => done(127));
		dsh.once('exit', (code) => done(code ?? 1));
	});

	if (Number.isInteger(targetPid)) {
		const processExists = () => {
			try {
				process.kill(targetPid, 0);
				return true;
			} catch (error) {
				return error?.code === 'EPERM';
			}
		};

		const findServer = async () => {
			try {
				return pickServer(
					JSON.parse(await readFile(serversFile, 'utf8')),
					targetPid,
					cwd,
					launchedAt,
				);
			} catch {
				return undefined;
			}
		};

		const inject = async () => {
			while (Date.now() < deadline && processExists()) {
				const server = await findServer();
				if (typeof server?.socketPath === 'string') {
					serverReadyAt ??= Date.now();
					if (Date.now() - serverReadyAt < 500) {
						await delay(50);
						continue;
					}
					try {
						await appendPrompt(server.socketPath, promptText(selected));
						return;
					} catch {
						// Discovery can become visible just before the socket accepts clients.
					}
				}
				await delay(50);
			}
		};

		void inject();
	}

	return exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	process.exit(await main());
}
