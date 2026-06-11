import { ActionBuilder } from './actionBuilder.js';
import { ActionResult } from './actionResult.js';
import { placeCommitProxy, mountActionRow } from './turnCommit.js';
import { TurnCast } from './turnCast.js';

// Turn Action panel — Item (turn_action_stub.md → Item).
//
// Thin host for the shared Action Builder, exactly like the Cast pane
// (turnCast.js) — and deliberately built on the same pipeline. The server
// precomputes the builder blob (GET /encounter/item_builder) listing the
// actor's carried Potions / Scrolls as castable options; this host mounts the
// builder and, on `action:confirmed`, POSTs the choices + rolled Successes to
// /encounter/resolve_cast with an `item` field identifying the Consumable.
//
// The Cast resolver does the heavy lifting (casting check, target Saves,
// Effects, Item-Form Magic Toxicity for Potions); the route additionally
// decrements the Consumable on commit. Confirm is two-stage exactly as Cast.
export class TurnItem {
  static ensureLoaded(container) {
    if (!container || container.dataset.tiLoaded) return;
    container.dataset.tiLoaded = '1';
    container._casterId = parseInt(container.getAttribute('data-actor-id'), 10);
    container._items = {};

    container.addEventListener('action:confirmed', (e) => TurnItem._preview(container, e.detail));
    container.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.ar-commit')) { e.preventDefault(); TurnItem._commit(container); }
    });
    // An area Item (a Scroll of an area spell) places its footprint on the map
    // exactly like casting it — the caught creatures become the Save Opposers.
    document.addEventListener('cast:area-placed', (e) => TurnItem._areaPlaced(container, e.detail || {}));

    container.innerHTML = '<p class="ta-attack-loading">Loading items…</p>';
    fetch('/encounter/item_builder?actor_id=' + encodeURIComponent(container._casterId), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        container.innerHTML = html + '<div class="ta-result ti-result tc-result" hidden></div>';
        const builder = container.querySelector('.action-builder');
        if (builder) {
          // Stash the key→Item map the builder carries (added by build_cast_blob)
          // so a confirmed choice maps back to the Consumable it cast.
          try { container._items = (JSON.parse(builder.dataset.builder || '{}').items) || {}; } catch (_e) { container._items = {}; }
          ActionBuilder.ensureLoaded(builder);
          container._builder = builder;
          const panel = container.closest && container.closest('.turn-action');
          mountActionRow(builder, (panel && panel.dataset.actionLabel) || 'Item');
        } else { container.innerHTML = '<p class="ta-warn">This Combatant carries no usable items.</p>'; }
      })
      .catch(() => { container.innerHTML = '<p class="ta-warn">Could not load the items.</p>'; });
  }

  // The Consumable behind the chosen "spell" option (the option value is its
  // unique key, "item:<ref>").
  static _item(container, choices) {
    return (container._items || {})[choices.spell] || null;
  }

  // The `item` block carried on the resolve payload (ref / owner / form / Tier).
  static _itemRef(item) {
    return item ? { ref: item.ref, owner_id: item.owner_id, form: item.form,
                    tier: item.tier, item_type: item.item_type, display: item.display } : null;
  }

  // Record an area placement and hand it to the builder, which lists the caught
  // creatures as the Target and gives each a Save Roll (mirrors TurnCast).
  static _areaPlaced(container, detail) {
    container._placement = detail;
    if (container._builder) ActionBuilder.areaPlaced(container._builder, container._casterId, detail);
  }

  // Translate the builder's confirmed choices + rolls into a resolve_cast
  // payload that names the Item. Mirrors TurnCast._payload, but the rolled
  // "spell" is the Item's Spell and the payload carries the Item ref/owner/form.
  static _payload(container, detail, commit) {
    const choices = detail.choices || {};
    const rolls = detail.rolls || [];
    const item = TurnItem._item(container, choices);
    const spellName = item ? item.spell : choices.spell;
    const caster = rolls.find((r) => r.id === 'caster') || {};

    // Area Item: the placed footprint determines the affected creatures (the
    // Spread Opposers). Each caught creature's Save nets against the cast
    // independently; send the placement point + each creature's Save successes.
    if (container._placement) {
      const p = container._placement;
      const targets = rolls
        .filter((r) => String(r.id).indexOf('save-') === 0)
        .map((r) => ({ id: parseInt(String(r.id).replace('save-', ''), 10), save: { successes: r.successes } }));
      return {
        commit: commit,
        spell_name: spellName,
        spell: { name: spellName, tier: item ? item.tier : null },
        item: TurnItem._itemRef(item),
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
      target.save = { successes: tgtRoll ? tgtRoll.successes : 0 };
    } else if (defType === 'dodge' || defType === 'block') {
      target.defense = { choice: defType, successes: tgtRoll ? tgtRoll.successes : 0,
                         dice: tgtRoll ? tgtRoll.dice_count : 0, speed: tgtRoll ? (tgtRoll.speed || 0) : 0 };
    } else if (defType === 'none') {
      target.defense = { choice: 'none' };
    }

    return {
      commit: commit,
      spell_name: spellName,
      spell: { name: spellName, tier: item ? item.tier : null },
      item: TurnItem._itemRef(item),
      luck: ActionBuilder.luckSpends(choices),
      caster: { id: container._casterId, dice: caster.dice_count, speed: caster.speed || 0, successes: caster.successes },
      targets: choices.target != null ? [target] : []
    };
  }

  static _preview(container, detail) {
    container._lastDetail = detail;
    if (detail.noRoll && !detail.auto) { TurnItem._commit(container); return; }
    TurnItem._post(container, TurnItem._payload(container, detail, false), (res) => TurnCast._renderResult(container, res, detail));
  }

  static _commit(container) {
    if (!container._lastDetail) return;
    const payload = TurnItem._payload(container, container._lastDetail, true);
    payload.override = TurnCast._gatherOverride(container);
    TurnItem._post(container, payload, () => window.location.reload());
  }

  static _post(container, payload, onOk) {
    if (!payload.spell_name) { TurnItem._warn(container, 'Pick an item first.'); return; }
    fetch('/encounter/resolve_cast', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    })
      .then((r) => r.json().catch(() => null))
      .then((res) => {
        if (!res || res.ok === false) { TurnItem._warn(container, (res && res.error) || 'Could not use the item.'); return; }
        onOk(res);
      })
      .catch(() => TurnItem._warn(container, 'Could not use the item.'));
  }

  static _warn(container, msg) {
    const slot = container.querySelector('.ti-result');
    if (slot) { slot.hidden = false; slot.innerHTML = `<p class="ta-warn">${esc(msg)}</p>`; }
  }
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}
