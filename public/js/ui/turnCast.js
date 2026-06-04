import { CheckBuilder } from './checkBuilder.js';

// Turn Action panel — Cast (turn_action_stub.md → Cast).
//
// Thin host for the shared Check Resolution Builder, exactly like the Attack
// pane (turnAttack.js). The server precomputes the builder blob
// (GET /encounter/cast_builder) with Target / Spell+dice / Defense steps; this
// host mounts the builder and, on `check:confirmed`, POSTs the choices +
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

    container.addEventListener('check:confirmed', (e) => TurnCast._preview(container, e.detail));
    container.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.ta-commit')) { e.preventDefault(); TurnCast._commit(container); }
      // "Change" re-arms map placement with the last footprint.
      if (e.target.closest && e.target.closest('.tc-replace') && container._areaArm) {
        e.preventDefault();
        document.dispatchEvent(new CustomEvent('cast:arm-area', { detail: container._areaArm }));
      }
    });
    // Remember the armed footprint (for "Change") and capture the placement.
    document.addEventListener('cast:arm-area', (e) => { container._areaArm = e.detail || null; });
    document.addEventListener('cast:area-placed', (e) => TurnCast._areaPlaced(container, e.detail || {}));

    container.innerHTML = '<p class="ta-attack-loading">Loading spells…</p>';
    fetch('/encounter/cast_builder?caster_id=' + encodeURIComponent(container._casterId), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        container.innerHTML = html + '<div class="ta-result tc-result" hidden></div>';
        const builder = container.querySelector('.check-builder');
        if (builder) CheckBuilder.ensureLoaded(builder);
        else container.innerHTML = '<p class="ta-warn">This Combatant knows no castable spells.</p>';
      })
      .catch(() => { container.innerHTML = '<p class="ta-warn">Could not load the cast.</p>'; });
  }

  // Record an area placement: stash it for the payload and list the caught
  // creatures (with a Change button to re-place) under the builder.
  static _areaPlaced(container, detail) {
    container._placement = detail;
    const slot = container.querySelector('.tc-result');
    if (!slot) return;
    const hits = detail.hits || [];
    const names = hits.length
      ? hits.map((h) => esc(h.label || ('#' + h.combatant_id))).join(', ')
      : '<em>no creatures caught</em>';
    slot.innerHTML =
      '<p class="tc-line"><strong>Spell effect placed.</strong> Affected: ' + names + '</p>' +
      '<div class="ta-actions"><button type="button" class="ce-btn tc-replace">Change</button></div>';
    slot.hidden = false;
  }

  // Translate the builder's confirmed choices + rolls into a resolve_cast payload.
  static _payload(container, detail, commit) {
    const choices = detail.choices || {};
    const rolls = detail.rolls || [];
    const spellName = choices.spell;
    const caster = rolls.find((r) => r.id === 'caster') || {};

    // Area Spell: the placed footprint determines the affected creatures; there
    // is no single Target. Send the placement point + the caught Combatants.
    if (container._placement) {
      const p = container._placement;
      return {
        commit: commit,
        spell_name: spellName,
        spell: { name: spellName },
        luck: CheckBuilder.luckSpends(choices),
        caster: { id: container._casterId, dice: caster.dice_count, speed: caster.speed || 0, successes: caster.successes },
        placement: { x: p.x, y: p.y },
        targets: (p.hits || []).map((h) => ({ id: h.combatant_id }))
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
      luck: CheckBuilder.luckSpends(choices),
      caster: { id: container._casterId, dice: caster.dice_count, speed: caster.speed || 0, successes: caster.successes },
      targets: choices.target != null ? [target] : []
    };
  }

  static _preview(container, detail) {
    container._lastDetail = detail;
    TurnCast._post(container, TurnCast._payload(container, detail, false), (res) => TurnCast._renderResult(container, res));
  }

  static _commit(container) {
    if (!container._lastDetail) return;
    TurnCast._post(container, TurnCast._payload(container, container._lastDetail, true), () => window.location.reload());
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

  static _renderResult(container, res) {
    const slot = container.querySelector('.tc-result');
    if (!slot) return;
    const lines = [];
    const tox = res.toxicity || {};
    lines.push(`<p class="tc-line"><strong>${esc(res.spell || 'Spell')}</strong> — ${esc(res.cast_skill || '')}` +
      ` · Mana ${num(res.mana_spent)}${tox.requested ? ` · Toxicity ${num(tox.requested)}${tox.accepted === false ? ' (blocked)' : ''}` : ''}</p>`);
    (res.targets || []).forEach((t) => {
      const fx = (t.applied || []).map((a) => TurnCast._fxText(a)).filter(Boolean).join(', ');
      lines.push(`<p class="tc-line">#${t.id}: ${esc(t.outcome)}${fx ? ' — ' + fx : ''}</p>`);
    });
    if (res.sustain) lines.push(`<p class="tc-line">Sustain: ${esc(res.sustain.kind)}</p>`);
    lines.push(`<div class="ta-actions"><button type="button" class="ce-btn ta-commit">Commit cast</button></div>`);
    slot.innerHTML = lines.join('');
    slot.hidden = false;
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
