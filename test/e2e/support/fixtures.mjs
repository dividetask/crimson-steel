import { test as base, expect } from '@playwright/test';
import { seedCampaign, removeCampaign } from './campaign.mjs';
import { startServer } from './server.mjs';

// Browser-test fixtures. See docs/project/browser_tests.md.
//
// Each test gets its own server and its own Campaign directory, so tests
// cannot leak state into one another and none of them can touch the DM's
// real campaign.

export const test = base.extend({
  // Files layered over the default Campaign — see seedCampaign.
  //   test.use({ campaign: { 'creatures_data_pcs.yaml': 'test/e2e/campaign/duo.yaml' } })
  campaign: [{}, { option: true }],

  app: async ({ campaign }, use) => {
    const dir = seedCampaign(campaign);
    const server = await startServer(dir);
    try {
      await use(server);
    } finally {
      await server.stop();
      removeCampaign(dir);
    }
  },

  baseURL: async ({ app }, use) => {
    await use(app.baseURL);
  },

  // The DM's browser. Requests come from loopback, which is the whole of
  // the DM identification rule, so there is nothing to log in to.
  dm: async ({ page, app, browser }, use) => {
    await use(new DungeonMaster(page, app, browser));
  },
});

export { expect };

class DungeonMaster {
  constructor(page, app, browser) {
    this.page = page;
    this.app = app;
    this.browser = browser;
  }

  // Arm the outcome of rolls the *server* makes — Initiative Strings, and
  // the seed behind a Random Encounter Table's `1d3 + 1`. Call before the
  // click that triggers the roll.
  //
  //   await dm.armRolls({ initiative: { 'Thora Stoneveil': 'XX9853' } })
  async armRolls(payload) {
    const res = await this.page.request.post(`${this.app.baseURL}/__test__/rolls`, {
      data: payload,
    });
    expect(res.ok(), `arming rolls failed: ${await res.text()}`).toBeTruthy();
    return res.json();
  }

  // Queue the dice the *browser* rolls, in the order the page asks for
  // them (see public/js/randomRng.js). Survives navigation: re-armed on
  // every document, so a queue set before a page load is the queue that
  // page rolls with.
  async scriptDice(values) {
    this.dice = values;
    await this.page.addInitScript((v) => { window.__scriptedDice = [...v]; }, values);
    await this.page.evaluate((v) => {
      window.__scriptedDice = [...v];
      window.__scriptedDiceExhausted = false;
    }, values).catch(() => {});
  }

  // Fails the test if the page rolled more dice than the queue held —
  // otherwise the extra dice would be random and the test flaky.
  async assertDiceNotExhausted() {
    const exhausted = await this.page.evaluate(() => !!window.__scriptedDiceExhausted);
    expect(exhausted, 'the page rolled more dice than the test queued').toBe(false);
  }

  // How many queued dice are left — useful for asserting a step rolled
  // exactly as many dice as expected.
  async diceRemaining() {
    return this.page.evaluate(() => (window.__scriptedDice || []).length);
  }

  // The Combat Tracker as the DM sees it. Returns one entry per
  // Combatant: [{ name: 'Ogre Brute', initiative: '—' }, ...].
  //
  // The Tracker only renders in the Combat Phase, so a peek from a Phase
  // like Downtime would read an empty table whether or not anyone is on
  // the roster — a check that always passes and proves nothing. This
  // reads it in a separate browser context, where it can set that
  // session's private DM Phase override to Combat (the "My view"
  // dropdown, which changes only the DM's own view) without disturbing
  // the Phase or the page the test is driving.
  async combatTracker() {
    const context = await this.browser.newContext({ baseURL: this.app.baseURL });
    try {
      const peek = await context.newPage();
      await peek.goto('/encounter');
      await peek.request.post('/encounter/dm_phase', { form: { phase: 'combat' } });
      await peek.goto('/encounter');
      return await peek.locator('tr.initiative-row').evaluateAll((rows) =>
        rows.map((row) => ({
          name: (row.querySelector('.initiative-col-name') || {}).textContent?.trim() || '',
          initiative: (row.querySelector('.initiative-col-init') || {}).textContent?.trim() || '',
          hp: (row.querySelector('.initiative-col-hp') || {}).textContent?.replace(/\s+/g, ' ').trim() || '',
        })),
      );
    } finally {
      await context.close();
    }
  }

  // Combatant names on the tracker, e.g. ['Thora Stoneveil', 'Ogre', 'Ogre'].
  async combatantNames() {
    return (await this.combatTracker()).map((row) => row.name);
  }

  // ---------------- the Encounter page ----------------

  // The party Phase, from the menu bar. Not the DM's private "My view"
  // override — this is the Phase everyone sees.
  // These controls submit a form and the page comes back changed. Each
  // waits for the change it asked for rather than for a load state:
  // the select auto-submits on change, so a load state can resolve on the
  // document being navigated away from and leave the next step looking at
  // a page that is about to be replaced.
  async setPartyPhase(phase) {
    const select = this.page.locator(
      'form.phase-form[action="/encounter/set_phase"] select.phase-select',
    );
    await select.selectOption(phase);
    await expect
      .poll(() => select.inputValue(), { timeout: 10_000, message: `Phase never became ${phase}` })
      .toBe(phase);
  }

  async rollInitiative() {
    await this.page.getByRole('button', { name: 'Roll Init' }).click();
    await expect
      .poll(
        async () => {
          const inits = await this.page
            .locator('tr.initiative-row .initiative-col-init')
            .allTextContents();
          return inits.length > 0 && inits.every((t) => t.trim() && t.trim() !== '—');
        },
        { timeout: 10_000, message: 'Initiative never landed on the Tracker' },
      )
      .toBe(true);
  }

  async startCombat() {
    await this.page.getByRole('button', { name: /start combat/i }).click();
    await this.page.locator('h3.ta-title').waitFor({ state: 'visible', timeout: 10_000 });
  }

  // Get Combat to its first turn.
  //
  // Roll Init is meant to do this on its own; today it only rolls, and
  // Start Combat is what begins the first turn (and rerolls Initiative on
  // the way, which is why the armed Strings are still the ones that land).
  // combat_start.spec.mjs holds that expectation on its own and is marked
  // test.fail() until it holds. Every other test comes through here, so
  // when Roll Init begins the turn there is one line to delete.
  async beginCombat() {
    await this.rollInitiative();
    await this.startCombat();
  }

  // Whose turn the Turn Action panel says it is, without the possessive:
  // "Thora Stoneveil".
  async actingCombatant() {
    const title = this.page.locator('h3.ta-title');
    // Bounded: with no Turn Action panel on the page — Combat not started,
    // say — an unbounded read would hang until the test times out, and a
    // timed-out test is a hard failure even under test.fail().
    await title.waitFor({ state: 'visible', timeout: 10_000 });
    return (await title.innerText()).replace(/[’']s Turn.*$/s, '').trim();
  }

  // End Turn — two presses, the same two the DM makes: the first opens
  // the End Turn confirm screen, the second confirms it.
  async endTurn() {
    const acting = await this.actingCombatant();
    await this.page.locator('button.ta-menu-btn[data-ta-action="end_turn"]').click();
    const confirm = this.page
      .locator('.turn-action button.ta-confirm:visible')
      .filter({ hasText: /^End Turn$/ })
      .last();
    await confirm.waitFor({ state: 'visible' });
    await Promise.all([this.page.waitForLoadState('domcontentloaded'), confirm.click()]);
    // The turn only really ended once the panel names someone else.
    await expect
      .poll(async () => this.actingCombatant(), { timeout: 10_000 })
      .not.toBe(acting);
  }

  // Open one of the Turn Action panel's actions (attack, move, cast, item,
  // end_turn) and return the pane it drives.
  async openAction(key) {
    await this.page.locator(`button.ta-menu-btn[data-ta-action="${key}"]`).click();
    const pane = this.page.locator(`.ta-${key}`);
    await pane.waitFor({ state: 'visible' });
    return new ActionBuilderPane(this.page, pane);
  }

  // Creatures spawned into the Campaign — the rows the roster sidebar
  // shows under a template with a "−" (delete) button, as opposed to the
  // template itself. A rolled encounter that has only been previewed
  // should not have created any.
  async spawnedCreatures(page = this.page) {
    return page
      .locator('li.cs-roster-row[data-roster-kind="spawned"] a.cs-roster-name')
      .allTextContents()
      .then((names) => names.map((n) => n.trim()));
  }
}

// One Action Builder pane (Cast, Attack, Item, ...).
//
// The builder walks a fixed set of steps and only ever shows the options
// for the step it is on, so a test drives it the way the DM does: click
// the option you want by its label, in order.
class ActionBuilderPane {
  constructor(page, root) {
    this.page = page;
    this.root = root;
  }

  // The step the builder is waiting on — both halves of it: the header
  // quick-picks in `.step-controls` ("Slam", which takes the default dice)
  // and the full option list in `.step-body` ("Slam (speed 0)", then a
  // dice count). Scoping to the active step is what keeps a label like
  // "No defense" — offered by both the target's own defense step and the
  // Ally Defense step — unambiguous.
  activeStep() {
    return this.root.locator('[data-step][data-state="active"]');
  }

  // The options on offer right now.
  async options() {
    const texts = await this.activeStep().locator('.cb-opt').allTextContents();
    return texts.map((t) => t.replace(/\s+/g, ' ').trim());
  }

  // Click one of them. `label` matches the whole option label unless a
  // RegExp is given.
  async pick(label) {
    const matcher = label instanceof RegExp ? label : new RegExp(`^${escapeRegExp(label)}$`);
    const options = () => this.activeStep().locator('.cb-opt').filter({ hasText: matcher });
    await expect
      .poll(() => options().count(), {
        timeout: 10_000,
        message: `the builder never offered "${label}"`,
      })
      .toBeGreaterThan(0);
    await options().first().click();
    await this.page.waitForTimeout(150); // the step machine re-renders
  }

  // Each Roll the builder is about to make: { id, side, dice, tn }.
  async rolls() {
    return this.root.locator('tbody.roll-group').evaluateAll((groups) =>
      groups.map((group) => {
        const config = JSON.parse(group.dataset.config || '{}');
        return {
          id: group.dataset.rollId,
          side: group.dataset.side,
          dice: config.dice_count,
          tn: config.tn,
          excluded: group.classList.contains('roll-group-excluded'),
        };
      }),
    );
  }

  async rollAll() {
    await this.root.locator('button.btn-roll-all:visible').first().click();
    await this.page.waitForTimeout(300);
  }

  // Press a button and wait for the resolution it triggers, rather than
  // for a load state: a cast with no Roll previews and commits in one
  // press and then reloads the page, so a plain wait races the reload.
  // `commit` picks which POST to wait for: a rolled action previews
  // first (commit:false) and applies on a second press, while an action
  // with no Roll — a Bonus-Action cast like Standard Shield — previews
  // and applies in the same press.
  async #press(button, { commit }) {
    await button.waitFor({ state: 'visible' });
    const responded = this.page.waitForResponse((res) => {
      if (!/\/encounter\/(resolve_cast|resolve_attack|use_special)/.test(res.url())) return false;
      if (res.request().method() !== 'POST') return false;
      const posted = res.request().postData() || '';
      return commit ? /"commit":\s*true/.test(posted) : true;
    }, { timeout: 15_000 });
    await button.click();
    const response = await responded;
    const body = await response.json().catch(() => ({}));
    // A committed action reloads the page under it.
    if (body.committed) await this.page.waitForLoadState('load');
    else await this.page.waitForTimeout(200);
    return body;
  }

  // Confirm the rolls — a preview for a rolled action.
  async confirm() {
    return this.#press(this.root.locator('button.btn-confirm:visible').first(), { commit: false });
  }

  // The result screen's text, for asserting on what the DM is shown.
  async resultText() {
    return (await this.root.innerText()).replace(/\s+/g, ' ');
  }

  // The button that applies the action for real. Returns the resolver's
  // response so a test can assert on what the server actually did.
  async commit(name) {
    return this.#press(
      this.root.locator('button:visible').filter({ hasText: name }).first(),
      { commit: true },
    );
  }
}

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
