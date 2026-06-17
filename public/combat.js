// Combat encounter stub demo — the documented step machine, driven entirely
// by the embedded sample blob (docs/website_design/combat/). Self-contained:
// it reads no server data. Nothing is persisted; Commit is a demo no-op.
(function () {
  'use strict';
  var root = document.querySelector('.ta-flow');
  var blobEl = document.getElementById('combat-blob');
  if (!root || !blobEl) return;
  var B = JSON.parse(blobEl.textContent);
  var DIE = B.config.die_size, BASE_TN = B.config.base_target_number;

  // ---- flow state ----
  var choices = {};                 // accumulated picks, keyed by step key
  var rows = [];                    // completed steps: {id, key, label, value}
  var active = { step: 'action' };  // current node: {step} or {roll}/{confirm,text}

  function poolLeft() {
    var spent = (choices.dice || 0) + (choices.defenceDice || 0);
    return B.combatant.pool.remaining - spent;
  }

  // ---- step catalog: each returns option groups, records a pick, and names
  // the next node. A group is { heading?, opts:[{value,label,disabled,note}] }.
  var STEPS = {
    action: {
      label: 'Action', key: 'action',
      groups: function () {
        var inc = B.combatant.incapacitated;
        var opts = inc ? [] : [{ value: 'attack', label: 'Attack' }, { value: 'move', label: 'Move' }]
          .concat((B.spells || []).length ? [{ value: 'cast', label: 'Cast' }] : [])
          .concat((B.items || []).length ? [{ value: 'item', label: 'Item' }] : [])
          .concat((B.active_spells || []).length ? [{ value: 'active_spells', label: 'Active Spells' }] : [])
          .concat((B.specials || []).length ? [{ value: 'special', label: 'Special Abilities' }] : []);
        opts.push({ value: 'end_turn', label: 'End Turn' });
        return [{ opts: opts }];
      },
      summary: function (v) {
        var o = this.groups()[0].opts.filter(function (x) { return x.value === v; })[0];
        return o ? o.label : v;
      },
      next: function (v) {
        switch (v) {
          case 'attack': case 'active_spells': return { step: 'target' };
          case 'cast': return { step: 'spell' };
          case 'item': return { step: 'item' };
          case 'special': return { step: 'special' };
          case 'move': return { confirm: 'Spend ' + B.config.move_cost + ' Combat Pool dice to Move.' };
          case 'end_turn': return { confirm: 'Advance to the next Combatant in initiative order.' };
        }
      }
    },

    special: {
      label: 'Special Ability', key: 'special',
      groups: function () {
        return [{ opts: (B.specials || []).map(function (s) {
          return { value: s.name, label: s.name + ' (' + s.activation + ')' };
        }) }];
      },
      summary: function (v) { return v; },
      next: function (v) {
        var s = (B.specials || []).filter(function (x) { return x.name === v; })[0];
        if (s.kind === 'channeled') { choices.actorName = s.name; return { step: 'dice' }; }
        if (s.kind === 'named') return { confirm: 'Apply ' + s.name + '.' };
        return { confirm: 'Use ' + s.name + '; the DM resolves its targets and saves.' };
      }
    },

    target: {
      label: 'Target', key: 'target',
      groups: function () {
        return [{ opts: B.targets.map(function (t) {
          return { value: String(t.id), label: t.name + (t.side === 'enemy' ? ' (enemy)' : ' (ally)') };
        }) }];
      },
      summary: function (v) { return tname(v); },
      next: function () { return afterPrimaryTarget(); }
    },

    weapon: {
      label: 'Weapon & Dice', key: 'weapon',
      groups: function () {
        return B.weapons.map(function (w) {
          var opts = [];
          for (var n = 2; n <= w.dice_cap; n++) {
            opts.push({ value: w.name + '|' + n, label: n + ' dice',
              disabled: (w.speed + n) > B.combatant.pool.remaining });
          }
          return { heading: w.name + ' · ' + w.kind + ' · Speed ' + w.speed, opts: opts };
        });
      },
      summary: function (v) { var p = v.split('|'); return p[0] + ' — ' + p[1] + ' dice'; },
      next: function (v) {
        var p = v.split('|'); var w = wpn(p[0]);
        choices.actorName = w.name; choices.dice = +p[1]; choices.kind = w.kind;
        return { step: 'defence' };
      }
    },

    spell: {
      label: 'Cast', key: 'spell',
      groups: function () {
        var byTier = {};
        B.spells.forEach(function (s) { (byTier[s.tier] = byTier[s.tier] || []).push(s); });
        return Object.keys(byTier).sort().map(function (t) {
          var mana = byTier[t][0].mana;
          return { heading: 'Tier ' + t + ' (' + mana + ' mana)',
            opts: byTier[t].map(function (s) {
              return { value: s.name, label: s.name, disabled: s.mana > B.combatant.mana.remaining };
            }) };
        });
      },
      summary: function (v) { return v; },
      next: function (v) {
        var s = spell(v); choices.spell = s; choices.actorName = s.skill;
        if (s.resolution === 'buff') return { confirm: 'Cast ' + s.name + ' (no roll).' };
        return { step: 'dice' };
      }
    },

    item: {
      label: 'Item', key: 'item',
      groups: function () {
        return [{ opts: B.items.map(function (i) {
          return { value: i.name, label: i.name + ' ×' + i.qty };
        }) }];
      },
      summary: function (v) { return v; },
      next: function (v) { choices.spell = item(v); choices.actorName = (item(v).skill || 'Item'); return { step: 'dice' }; }
    },

    dice: {
      label: 'Dice', key: 'dice',
      groups: function () {
        var cap = (choices.spell && choices.spell.dice_cap) || 6;
        var min = (choices.action === 'cast' || choices.action === 'item') ? 4 : 2;
        var opts = [];
        for (var n = min; n <= cap; n++) opts.push({ value: String(n), label: n + ' dice', disabled: n > B.combatant.pool.remaining });
        return [{ heading: ((choices.spell && choices.spell.skill) || 'Channel') + ' check', opts: opts }];
      },
      summary: function (v) { return v + ' dice'; },
      next: function (v) {
        choices.dice = +v;
        if (choices.action === 'cast' || choices.action === 'item') return targetingNode();
        return { roll: true }; // channeled special
      }
    },

    area: {
      label: 'Area', key: 'targets',
      groups: function () { return [{ opts: [{ value: 'placed', label: 'Place the area (2 creatures caught)' }] }]; },
      summary: function () { return '2 creatures caught'; },
      next: function () { return afterSpellTargets(); }
    },

    multi: {
      label: 'Targets', key: 'targets',
      groups: function () {
        return [{ opts: B.targets.filter(function (t) { return t.side === 'enemy'; }).map(function (t) {
          return { value: String(t.id), label: t.name, toggle: true };
        }).concat([{ value: '__done', label: 'Done' }]) }];
      },
      multi: true,
      summary: function (v) { return v.length + ' chosen'; },
      next: function () { return afterSpellTargets(); }
    },

    defence: {
      label: 'Defence', key: 'defence',
      groups: function () {
        var elig = B.defences.filter(function (d) { return d.kinds.indexOf(choices.kind || 'spell') >= 0; });
        var groups = [{ opts: [{ value: 'none', label: 'No defense' }] }];
        elig.forEach(function (d) {
          var opts = [];
          var max = Math.min(d.dice_cap, poolLeft());
          for (var n = 2; n <= max; n++) opts.push({ value: d.name + '|' + n, label: n + ' dice' });
          groups.push({ heading: d.name + ' · Speed ' + d.speed, opts: opts.length ? opts : [{ value: d.name + '|0', label: 'no pool', disabled: true }] });
        });
        return groups;
      },
      summary: function (v) { return v === 'none' ? 'No defense' : v.split('|')[0] + ' — ' + v.split('|')[1] + ' dice'; },
      next: function (v) {
        if (v !== 'none') { var p = v.split('|'); choices.defenceName = p[0]; choices.defenceDice = +p[1]; }
        return { step: 'luck' };
      }
    },

    luck: {
      label: 'Luck', key: 'luck',
      groups: function () {
        var opts = [{ value: 'none', label: 'No luck' }];
        (B.luck_sources || []).forEach(function (s) { opts.push({ value: s.name, label: s.name }); });
        return [{ opts: opts }];
      },
      summary: function (v) { return v === 'none' ? 'No luck' : v; },
      next: function () { return { roll: true }; }
    }
  };

  // ---- branch helpers ----
  function afterPrimaryTarget() {
    if (choices.action === 'attack' || choices.action === 'active_spells') return { step: 'weapon' };
    return afterSpellTargets(); // cast/item, single target
  }
  function targetingNode() {
    var s = choices.spell;
    if (s.targeting === 'self' || s.target === 'self') return afterSpellTargets();
    if (s.targeting === 'area') return { step: 'area' };
    if (s.targeting === 'multi') return { step: 'multi' };
    return { step: 'target' };
  }
  function afterSpellTargets() {
    var r = (choices.spell && choices.spell.resolution);
    if (r === 'attack') return { step: 'defence' };
    return { step: 'luck' }; // save / utility both still roll the caster
  }

  // ---- lookups ----
  function tname(id) { var t = B.targets.filter(function (x) { return String(x.id) === String(id); })[0]; return t ? t.name : id; }
  function wpn(n) { return B.weapons.filter(function (x) { return x.name === n; })[0]; }
  function spell(n) { return B.spells.filter(function (x) { return x.name === n; })[0]; }
  function item(n) { return B.items.filter(function (x) { return x.name === n; })[0]; }

  // ---- rendering ----
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

  function render() {
    root.innerHTML = '';
    rows.forEach(function (r, i) {
      var row = el('div', 'ta-row');
      row.appendChild(el('span', 'ta-row-label', r.label + ':'));
      row.appendChild(el('span', 'ta-row-value', r.summaryText));
      var ch = el('button', 'ta-change'); ch.innerHTML = '&#8624; Change';
      ch.onclick = function () { changeTo(i); };
      row.appendChild(ch);
      root.appendChild(row);
    });
    if (active.step) renderStep(STEPS[active.step]);
    else if (active.roll) renderRoll();
    else if (active.confirm) renderConfirm(active.confirm);
  }

  function renderStep(def) {
    var panel = el('div', 'ta-panel');
    panel.appendChild(el('div', 'ta-panel-title', def.label));
    var picked = []; // for multi
    def.groups().forEach(function (g) {
      if (g.heading) panel.appendChild(el('div', 'ta-group-head', g.heading));
      var line = el('div', 'ta-line');
      g.opts.forEach(function (o) {
        var b = el('button', 'ta-btn' + (o.toggle ? ' ta-toggle' : ''), o.label);
        if (o.disabled) { b.disabled = true; b.classList.add('ta-disabled'); }
        b.onclick = function () {
          if (def.multi) {
            if (o.value === '__done') { commitStep(def, picked.slice()); return; }
            b.classList.toggle('ta-on');
            var idx = picked.indexOf(o.value);
            if (idx >= 0) picked.splice(idx, 1); else picked.push(o.value);
          } else {
            commitStep(def, o.value);
          }
        };
        line.appendChild(b);
      });
      panel.appendChild(line);
    });
    root.appendChild(panel);
  }

  function commitStep(def, value) {
    choices[def.key] = value;
    var next = def.next(value); // next() may also set derived choices
    rows.push({ id: active.step, key: def.key, value: value, label: def.label, summaryText: def.summary(value) });
    active = next;
    render();
  }

  function renderConfirm(text) {
    var panel = el('div', 'ta-panel');
    panel.appendChild(el('p', 'ta-lead', text));
    var b = el('button', 'ta-commit', 'Commit');
    b.onclick = function () { panel.replaceChild(el('p', 'ta-done', '✓ Committed (demo — nothing saved).'), b); };
    panel.appendChild(b);
    root.appendChild(panel);
  }

  function seedRolls() {
    var rolls = [{ name: choices.actorName || 'Action', dice: choices.dice || 4, tn: BASE_TN, side: 'supporting' }];
    if (choices.defenceName) rolls.push({ name: choices.defenceName, dice: choices.defenceDice, tn: BASE_TN, side: 'opposing' });
    else if (choices.spell && choices.spell.resolution === 'save') {
      var save = (choices.spell.save || 'Save') + ' save';
      if (choices.targets === 'placed' || (choices.targets && choices.targets.length)) {
        var n = choices.targets === 'placed' ? 2 : choices.targets.length;
        for (var i = 0; i < n; i++) rolls.push({ name: save + ' #' + (i + 1), dice: 5, tn: BASE_TN, side: 'opposing' });
      } else rolls.push({ name: save, dice: 5, tn: BASE_TN, side: 'opposing' });
    }
    return rolls;
  }

  function renderRoll() {
    var rolls = seedRolls();
    var panel = el('div', 'ta-panel');
    panel.appendChild(el('div', 'ta-panel-title', 'Roll'));
    var rollBtn = el('button', 'ta-commit', 'Roll All');
    panel.appendChild(rollBtn);
    var out = el('div'); panel.appendChild(out);
    rollBtn.onclick = function () {
      out.innerHTML = ''; rollBtn.remove();
      var sup = 0, opp = 0;
      rolls.forEach(function (r) {
        var dice = [], total = 0;
        for (var i = 0; i < r.dice; i++) {
          var d = 1 + Math.floor(Math.random() * DIE);
          dice.push(d);
          total += d === DIE ? 2 : (d >= r.tn ? 1 : (d === 1 ? -1 : 0));
        }
        if (r.side === 'supporting') sup += total; else opp += total;
        var line = el('div', 'ta-roll-line');
        line.appendChild(el('span', 'ta-roll-name', r.name + ' (' + r.dice + 'd vs ' + r.tn + ')'));
        line.appendChild(el('span', 'ta-roll-dice', dice.join(' ')));
        line.appendChild(el('span', 'ta-roll-total', (total >= 0 ? '+' : '') + total));
        out.appendChild(line);
      });
      var net = sup - opp;
      out.appendChild(el('div', 'ta-net', 'Net Degree of Success: ' + (net >= 0 ? '+' : '') + net));
      var commit = el('button', 'ta-commit', 'Commit');
      commit.onclick = function () { commit.replaceWith(el('p', 'ta-done', '✓ Committed (demo — nothing saved).')); };
      out.appendChild(commit);
    };
    root.appendChild(panel);
  }

  function changeTo(i) {
    var reopen = rows[i];
    for (var j = i; j < rows.length; j++) delete choices[rows[j].key];
    rows = rows.slice(0, i);
    active = { step: reopen.id };
    render();
  }

  render();
})();
