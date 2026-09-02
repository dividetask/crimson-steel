import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { REPO_ROOT } from './campaign.mjs';

// Boot the real app against a throwaway Campaign.
//
// The browser talks to the same Sinatra server a DM runs, started with:
//
//   CRIMSON_DATA_DIR       the test's Campaign directory
//   CRIMSON_ISOLATED_DATA  no shipped example data behind it
//   CRIMSON_TEST_MODE      mounts /__test__/* so a test can arm the
//                          outcome of the rolls the server makes
//
// It binds loopback, which is also how the app decides who the DM is
// (CLAUDE.md → "DM vs. player"), so a page driving 127.0.0.1 is the DM
// with no login step.

function freePort() {
  return new Promise((res, rej) => {
    const srv = createServer();
    srv.on('error', rej);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => res(port));
    });
  });
}

async function waitUntilUp(baseURL, child, timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  let lastError = 'no response';
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`server exited early (${child.exitCode}):\n${child.log}`);
    }
    try {
      const res = await fetch(`${baseURL}/encounter`, { redirect: 'manual' });
      if (res.status < 500) return;
      lastError = `HTTP ${res.status}`;
    } catch (err) {
      lastError = err.message;
    }
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error(`server never came up (${lastError}):\n${child.log}`);
}

export async function startServer(campaignDir) {
  const port = await freePort();
  const baseURL = `http://127.0.0.1:${port}`;

  const child = spawn(
    'bundle',
    ['exec', 'bin/puma', '-b', `tcp://127.0.0.1:${port}`, 'config.ru'],
    {
      cwd: REPO_ROOT,
      env: {
        ...process.env,
        CRIMSON_DATA_DIR: campaignDir,
        CRIMSON_ISOLATED_DATA: '1',
        CRIMSON_TEST_MODE: '1',
        RACK_ENV: 'production', // quiet the request log
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );

  child.log = '';
  const collect = (chunk) => { child.log += chunk.toString(); };
  child.stdout.on('data', collect);
  child.stderr.on('data', collect);

  await waitUntilUp(baseURL, child);

  return {
    baseURL,
    log: () => child.log,
    async stop() {
      if (child.exitCode !== null) return;
      child.kill('SIGTERM');
      await new Promise((res) => {
        const timer = setTimeout(() => { child.kill('SIGKILL'); res(); }, 5000);
        child.on('exit', () => { clearTimeout(timer); res(); });
      });
    },
  };
}
