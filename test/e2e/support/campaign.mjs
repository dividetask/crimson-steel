import { cpSync, mkdtempSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, isAbsolute, resolve } from 'node:path';

export const REPO_ROOT = resolve(new URL('../../..', import.meta.url).pathname);
export const DEFAULT_CAMPAIGN = join(REPO_ROOT, 'test/e2e/campaign/default');

// Build the Campaign one test runs against.
//
// Every test starts from `test/e2e/campaign/default` — a copy of the
// shipped example data with a clean slate for the session state (no
// Combatants, no damage, a fresh clock). A test that needs different data
// layers files over that copy:
//
//   test.use({ campaign: { 'creatures_data_pcs.yaml': 'test/e2e/campaign/two_pcs.yaml' } })
//   test.use({ campaign: { 'creatures_data_npcs.yaml': null } })          // remove
//   test.use({ campaign: { 'chronicle_data.json': '{"campaign_name":"X"}' } })  // inline
//
// A value is a repo-relative (or absolute) path to copy in, a string of
// file content, or null to drop the default file entirely.
//
// The result is a throwaway directory. The server is booted against it
// with CRIMSON_ISOLATED_DATA set, so the shipped example files do not
// stand behind it and the DM's own `data/` is neither read nor written.
export function seedCampaign(overrides = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'crimson-e2e-'));
  cpSync(DEFAULT_CAMPAIGN, dir, { recursive: true });

  for (const [name, value] of Object.entries(overrides)) {
    const target = join(dir, name);
    if (value === null || value === undefined) {
      rmSync(target, { force: true });
      continue;
    }
    const candidate = isAbsolute(value) ? value : join(REPO_ROOT, value);
    if (existsSync(candidate)) cpSync(candidate, target);
    else writeFileSync(target, String(value));
  }
  return dir;
}

export function removeCampaign(dir) {
  rmSync(dir, { recursive: true, force: true });
}
