import { ActionBuilder } from './actionBuilder.js';
import { ActionResult } from './actionResult.js';
import { placeCommitProxy } from './turnCommit.js';

// Turn Action panel — Cast (turn_action_stub.md → Cast).
//
// Thin host for the shared Action Builder, exactly like the Attack
// pane (turnAttack.js). The server precomputes the builder blob
// (GET /encounter/cast_builder) with Target / Spell+dice / Defense steps; this
// host mounts the builder and, on `action:confirmed`, POSTs the choices +
// rolled Successes to /encounter/resolve_cast. Confirm is two-stage:
//   1st Confirm -> non-mutating PREVIEW (commit:false); the outcome renders
//       beneath the still-present builder with a Commit button.
//   2nd Confirm -> "Commit cast" applies it for real (Combat Pool, Mana,
//       Magic Toxicity, Effects, sustain), then reloads.
export class TurnCast {
  static ensureLoaded(container) {
    if (!container || container.dataset.tcLoaded) return;
    container.dataset.tcLoaded = '1';
    container._casterId = parseInt(container.getAttribute('data-caster-id'), 10);

    container.addEventListener('action:confirmed', (e) => TurnCast._preview(container, e.detail));
    container.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.ar-commit')) { e.preventDefault(); TurnCast._commit(container); }
    });
    // Capture an area placement (re-placement re-fires via the Target step's
    // own Change button, which re-arms the "Place on the map" option).
    document.addEventListener('cast:area-placed', (e) => TurnCast._areaPlaced(container, e.detail || {}));

    container.innerHTML = '<p class="ta-attack-loading">Loading spells…</p>';
    fetch('/encounter/cast_builder?caster_id=' + encodeURIComponent(container._casterId), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        container.innerHTML = html + '<div class="ta-result tc-result" hidden></div>';
        const builder = container.querySelector('.action-builder');
        if (builder) { ActionBuilder.ensureLoaded(builder); container._builder = builder; }
        else container.innerHTML = '<p class="ta-warn">This Combatant knows no castable spells.</p>';
      })
      .catch(() => { container.innerHTML = '<p class="ta-warn">Could not load the cast.</p>'; });
  }

  // Record an area placement: stash it for the payload and hand it to the
  // builder, which lists the affected creatures as the Target and gives each a
  // Save (Opposed) Roll. No separate "placed" box.
  static _areaPlaced(container, detail) {
    container._placement = detail;
    if (container._builder) ActionBuilder.areaPlaced(container._builder, container._casterId, detail);
  }

  // Translate the builder's confirmed choices + rolls into a resolve_cast payload.
  static _payload(container, detail, commit) {
    const choices = detail.choices || {};
    const rolls = detail.rolls || [];
    const spellName = choices.spell;
    const caster = rolls.find((r) => r.id === 'caster') || {};

    // Area Spell: the placed footprint determines the affected creatures (the
    // Spread Opposers). Each caught creature's Save Roll nets against the cast
    // independently; send the placement point + each creature's Save successes.
    if (container._placement) {
      const p = container._placement;
      const targets = rolls
        .filter((r) => String(r.id).indexOf('save-') === 0)
        .map((r) => ({ id: parseInt(String(r.id).replace('save-', ''), 10), save: { successes: r.successes } }));
      return {
        commit: commit,
        spell_name: spellName,
        spell: { name: spellName },
        luck: ActionBuilder.luckSpends(choices),
        caster: { id: container._casterId, dice: caster.dice_count, speed: caster.speed || 0, successes: caster.successes },
        placement: { x: p.x, y: p.y },
        targets: targets
      };
    }

    const tgtRoll = rolls.find((r) => r.id === 'target');
    const defType = String(choices.defense == null ? '' : choices.defense).split('|')[0];

    const target = { id: choices.target };
    if (defType.indexOf('save') === 0) {
      // Save Spell: the target's Saving Throw nets against the casting check.
      target.save = { successes: tgtRoll ? tgtRoll.successes : 0 };
    } else if (defType === 'dodge' || defType === 'block') {
      // Attack-roll Spell with a declared Defensive Action.
      target.defense = { choice: defType, successes: tgtRoll ? tgtRoll.successes : 0,
                         dice: tgtRoll ? tgtRoll.dice_count : 0, speed: tgtRoll ? (tgtRoll.speed || 0) : 0 };
    } else if (defType === 'none') {
      // Attack-roll Spell, no defense declared (net vs zero).
      target.defense = { choice: 'none' };
    }

    return {
      commit: commit,
      spell_name: spellName,
      spell: { name: spellName },
      // Luck spent on this cast (one entry per source; source_id null = DM).
      luck: ActionBuilder.luckSpends(choices),
      caster: { id: container._casterId, dice: caster.dice_count, speed: caster.speed || 0, successes: caster.successes },
      targets: choices.target != null ? [target] : []
    };
  }

  static _preview(container, detail) {
    container._lastDetail = detail;
    // Every cast — even a no-roll one (a buff, or a reservoir pour like Shield) —
    // shows its result block first, so the DM sees and confirms the Combat Pool
    // and Mana it spends before committing, exactly like Attack and Move.
    TurnCast._post(container, TurnCast._payload(container, detail, false), (res) => TurnCast._renderResult(container, res));
  }

  static _commit(container) {
    if (!container._lastDetail) return;
    const payload = TurnCast._payload(container, container._lastDetail, true);
    payload.override = TurnCast._gatherOverride(container);
    TurnCast._post(container, payload, () => window.location.reload());
  }

  // Read the editable result fields (Mana, per-participant Combat Pool) into an
  // override the cast resolver applies on commit.
  static _gatherOverride(container) {
    const f = ActionResult.fields(container.querySelector('.tc-result'));
    const o = {};
    if ('mana' in f) o.mana = f.mana;
    const pools = Object.keys(f).filter((k) => k.indexOf('pool:') === 0)
      .map((k) => ({ id: num(k.slice(5)), amount: f[k] }));
    if (pools.length) o.pool_spends = pools;
    return o;
  }

  static _post(container, payload, onOk) {
    if (!payload.spell_name) { TurnCast._warn(container, 'Pick a spell first.'); return; }
    fetch('/encounter/resolve_cast', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    })
      .then((r) => r.json().catch(() => null))
      .then((res) => {
        if (!res || res.ok === false) { TurnCast._warn(container, (res && res.error) || 'Could not resolve the cast.'); return; }
        onOk(res);
      })
      .catch(() => TurnCast._warn(container, 'Could not resolve the cast.'));
  }

  // Render the cast outcome through the shared Action Result renderer — the same
  // markup the Attack result uses. Mana and per-participant Combat Pool are the
  // editable fields; the spell line, per-target outcomes, and sustain are
  // read-only notes.
  static _renderResult(container, res) {
    const slot = container.querySelector('.tc-result');
    if (!slot) return;
    const tox = res.toxicity || {};
    const nameOf = TurnCast._namer(container);
    const fields = [{ key: 'mana', label: 'Mana', value: num(res.mana_spent), editable: true }];
    (res.pool_spends || []).filter((s) => s.amount > 0).forEach((s) => {
      fields.push({ key: `pool:${s.id}`, label: `Combat Pool — ${nameOf(s.id)}`, value: num(s.amount), editable: true });
    });
    const notes = [{
      label: res.spell || 'Spell',
      value: (res.cast_skill || '') +
        (tox.requested ? ` · Toxicity ${num(tox.requested)}${tox.accepted === false ? ' (blocked)' : ''}` : '')
    }];
    (res.targets || []).forEach((t) => {
      const fx = (t.applied || []).map((a) => TurnCast._fxText(a)).filter(Boolean).join(', ');
      notes.push({ label: `#${t.id}`, value: `${t.outcome || ''}${fx ? ' — ' + fx : ''}` });
    });
    if (res.sustain) notes.push({ label: 'Sustain', value: res.sustain.kind });
    ActionResult.render(slot, { fields, notes, commitLabel: 'Commit cast' });
    slot.hidden = false;
    // Surface a Commit button at the top of the Turn Action stub (the action
    // menu's confirm slot) so the DM commits without reaching down here.
    placeCommitProxy(container, 'Commit cast');
  }

  static _fxText(a) {
    if (!a) return '';
    if (a.kind === 'damage') return `${num(a.amount)} ${a.damage_type || ''} (${splitText(a.severity_map)})`;
    if (a.kind === 'heal') return `heal ${splitText(a.severity_map || a.healed)}`;
    if (a.kind === 'mana') return `mana +${a.restored != null ? a.restored : a.amount}`;
    if (a.kind === 'temp_hp') return `temp HP ${num(a.amount)}`;
    if (a.kind === 'effect') return esc(a.name);
    return a.error ? `error: ${esc(a.error)}` : '';
  }

  static _warn(container, msg) {
    const slot = container.querySelector('.tc-result');
    if (slot) { slot.hidden = false; slot.innerHTML = `<p class="ta-warn">${esc(msg)}</p>`; }
  }

  // Resolve a Combatant id to a display name from the builder's roll groups (the
  // caster and any target), so the Combat-Pool rows read by name like Attack's.
  static _namer(container) {
    const map = {};
    container.querySelectorAll('.roll-group').forEach((g) => {
      const nm = g.querySelector('.creature-name');
      if (nm) map[g.dataset.rollId] = nameText(nm);
    });
    const choices = (container._lastDetail || {}).choices || {};
    const byId = {};
    byId[container._casterId] = map.caster || ('#' + container._casterId);
    if (choices.target != null) byId[choices.target] = map.target || ('#' + choices.target);
    return (id) => byId[id] || ('#' + id);
  }
}

// Read only the creature-name cell's own text nodes (excluding the .tn-tip
// tooltip span) so the TN computation text doesn't leak into the name.
function nameText(el) {
  let t = '';
  el.childNodes.forEach((n) => { if (n.nodeType === 3) t += n.textContent; });
  return t.trim() || el.textContent.trim();
}

function num(v) { const n = parseInt(v, 10); return Number.isNaN(n) ? 0 : n; }
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}
function splitText(sev) {
  sev = sev || {};
  const parts = ['minor', 'moderate', 'major'].filter((k) => sev[k]).map((k) => `${sev[k]} ${k}`);
  return parts.length ? parts.join(', ') : 'none';
}
