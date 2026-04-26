// Client-side state machine driving the melee_attack_stub flow.
//
// The Ruby helper renders an empty container and ships the stub config
// (attacker, targets, ally reactions, dice rules) on window.meleeAttackConfigs
// keyed by stub id. This file picks the config up at init time, walks the
// DM through the steps below, and dispatches `meleeattack:confirm` on the
// stub root with the full chosen payload at the end.
//
// Steps with a single (or zero) option auto-advance. Reaction steps
// with no options are skipped entirely. Roll steps embed the existing
// roll_stub partial via /roll_stub/render and listen for its
// `rollstub:confirm` event to capture the value.
(function() {
  function cfg(stubId)  { return (window.meleeAttackConfigs || {})[stubId]; }
  function rootEl(stubId){ return document.querySelector('.melee-attack-stub[data-stub-id="' + stubId + '"]'); }
  function stepsEl(stubId){ return document.getElementById('melee-steps-' + stubId); }

  // --- DOM helpers ---------------------------------------------------------

  function makeStep(label) {
    var step = document.createElement('div');
    step.className = 'melee-step';
    var head = document.createElement('div');
    head.className = 'melee-step-head';
    head.textContent = label;
    step.appendChild(head);
    var body = document.createElement('div');
    body.className = 'melee-step-body';
    step.appendChild(body);
    return { root: step, body: body };
  }

  // `kind` identifies a decision step so we can roll back to it later.
  // Roll steps and final/error states leave it unset and skip the
  // rollback button. The host stub id is stored on the step object so
  // lockStep can wire up the rollback handler without re-plumbing.
  function appendStep(stubId, label, kind) {
    var step = makeStep(label);
    if (kind) step.root.dataset.kind = kind;
    step.stubId = stubId;
    step.kind = kind || null;
    stepsEl(stubId).appendChild(step.root);
    if (step.root.scrollIntoView) {
      step.root.scrollIntoView({behavior: 'smooth', block: 'nearest'});
    }
    return step;
  }

  function lockStep(step, summary) {
    step.body.innerHTML = '';
    var sum = document.createElement('div');
    sum.className = 'melee-step-summary';
    sum.innerHTML = summary;
    step.body.appendChild(sum);
    step.root.classList.add('melee-step-locked');
    if (step.kind) {
      var back = document.createElement('button');
      back.type = 'button';
      back.className = 'melee-rollback-btn';
      back.title = 'Undo this decision and everything after it';
      back.innerHTML = '↶ Change';
      back.addEventListener('click', function() { rollbackTo(step.stubId, step.kind); });
      step.body.appendChild(back);
    }
  }

  // Map of decision-step kinds to the function that re-opens that step.
  // Built lazily so the function references resolve after declarations.
  function rollbackHandler(kind) {
    return ({
      target:          chooseTarget,
      weapon:          chooseWeapon,
      attackDice:      chooseAttackDice,
      defense:         chooseDefense,
      defenseDice:     chooseDefenseDice,
      allyReactions:   chooseAllyReactions,
      targetReactions: chooseTargetReactions,
      damage:          collectDamage
    })[kind];
  }

  // Drop the named decision step (most recent occurrence) and every
  // step that came after it, then re-run the handler that produced it.
  // The handler will rewrite any state fields the new flow touches; the
  // older state values for downstream steps stay around but get
  // overwritten as the user walks forward again.
  function rollbackTo(stubId, kind) {
    var container = stepsEl(stubId);
    if (!container) return;
    var node = container.querySelector('.melee-step[data-kind="' + kind + '"]');
    if (!node) return;
    while (node.nextSibling) container.removeChild(node.nextSibling);
    container.removeChild(node);
    var handler = rollbackHandler(kind);
    if (handler) handler(stubId);
  }

  function btn(label, onClick, extraClass) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'melee-btn' + (extraClass ? ' ' + extraClass : '');
    b.innerHTML = label;
    b.addEventListener('click', onClick);
    return b;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function(c) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  // Inject HTML returned by the server, then re-create any <script>
  // tags so they execute (innerHTML alone leaves them inert). Used for
  // the roll_stub partials we pull in via /roll_stub/render.
  function injectHtmlWithScripts(target, html) {
    target.innerHTML = html;
    target.querySelectorAll('script').forEach(function(oldScript) {
      var s = document.createElement('script');
      if (oldScript.src) s.src = oldScript.src;
      else s.textContent = oldScript.textContent;
      oldScript.parentNode.replaceChild(s, oldScript);
    });
  }

  function fetchRollPartial(params) {
    var body = new URLSearchParams();
    Object.keys(params).forEach(function(k) {
      if (params[k] !== undefined && params[k] !== null) body.append(k, params[k]);
    });
    return fetch('/roll_stub/render', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body.toString()
    }).then(function(r) {
      if (!r.ok) throw new Error('roll_stub render failed: ' + r.status);
      return r.text();
    });
  }

  // --- TN math (stays in the stub so the host can be ignorant) -------------

  function clampTn(stubId, raw) {
    // The stub doesn't enforce min/max TN — the dice resolution config
    // does that on the server. We just show what we calculated.
    return raw;
  }

  // Attack TN = base − attacker bonus − weapon attack bonus + defense bonus
  // (where "defense bonus" is the implement's attack_bonus, e.g. parry weapon).
  function attackTn(stubId, weapon, defense, isFlatfooted) {
    var c = cfg(stubId);
    var tn = c.baseTn
      - (c.attacker.skill.bonus | 0)
      - (weapon.attack_bonus | 0);
    if (isFlatfooted) tn -= 1;
    if (defense && defense.implement) tn += (defense.implement.attack_bonus | 0);
    return clampTn(stubId, tn);
  }

  // Defense TN = base − defender bonus + attacker bonus
  function defenseTn(stubId, weapon, defense) {
    var c = cfg(stubId);
    var tn = c.baseTn
      - ((defense.skill && defense.skill.bonus) | 0)
      + (weapon.attack_bonus | 0);
    if (defense.implement) tn -= (defense.implement.attack_bonus | 0);
    return clampTn(stubId, tn);
  }

  // --- Flow ---------------------------------------------------------------

  function start(stubId) {
    var c = cfg(stubId);
    if (!c) return;
    c.state = {
      target: null, weapon: null, attackDice: 0,
      defense: null, defenseDice: 0,
      allyReactions: [], allyResults: [],
      attackSuccesses: 0, defenseSuccesses: 0,
      targetReactions: [],
      damage: 0, bleed: 0, threshold: 0, afflictions: []
    };
    stepsEl(stubId).innerHTML = '';
    chooseTarget(stubId);
  }

  // --- Step 1: Target ------------------------------------------------------
  function chooseTarget(stubId) {
    var c = cfg(stubId);
    var step = appendStep(stubId, 'Select Target', 'target');
    var pick = function(t) {
      c.state.target = t;
      lockStep(step, 'Target: <strong>' + escapeHtml(t.name) + '</strong>');
      chooseWeapon(stubId);
    };
    if (c.targets.length === 0) {
      step.body.textContent = 'No valid targets.';
      return;
    }
    if (c.targets.length === 1) {
      pick(c.targets[0]);
      return;
    }
    c.targets.forEach(function(t) {
      var label = escapeHtml(t.name) + (t.incapacitated ? ' <em>(incapacitated)</em>' : '');
      step.body.appendChild(btn(label, function() { pick(t); }));
    });
  }

  // --- Step 2: Weapon ------------------------------------------------------
  function chooseWeapon(stubId) {
    var c = cfg(stubId);
    var weapons = c.attacker.weapons || [];
    var step = appendStep(stubId, 'Select Weapon', 'weapon');
    var pick = function(w) {
      c.state.weapon = w;
      lockStep(step, 'Weapon: <strong>' + escapeHtml(w.name) + '</strong>' +
        ' <span class="melee-meta">(atk +' + (w.attack_bonus|0) +
        ', dmg ' + (w.damage|0) +
        ', threshold ' + (w.threshold|0) +
        ', bleed ' + (w.bleed|0) +
        ', spd ' + (w.speed|0) + ')</span>');
      chooseAttackDice(stubId);
    };
    if (weapons.length === 0) {
      step.body.textContent = 'Attacker has no equipped melee weapons.';
      return;
    }
    if (weapons.length === 1) { pick(weapons[0]); return; }
    weapons.forEach(function(w) {
      step.body.appendChild(btn(escapeHtml(w.name), function() { pick(w); }));
    });
  }

  // --- Step 3: Attack dice count ------------------------------------------
  function chooseAttackDice(stubId) {
    var c = cfg(stubId);
    var w = c.state.weapon;
    var min = w.min_dice | 0;
    var max = Math.min(w.max_dice | 0, c.attacker.skill.dice | 0);
    var step = appendStep(stubId, 'Attack Dice (' + min + '–' + max + ')', 'attackDice');
    if (max < min) {
      step.body.textContent = 'No valid attack dice count.';
      return;
    }
    var commit = function(n) {
      c.state.attackDice = n;
      lockStep(step, 'Attack dice: <strong>' + n + '</strong>');
      chooseDefense(stubId);
    };
    if (min === max) { commit(min); return; }
    var hint = document.createElement('span');
    hint.className = 'melee-meta';
    hint.textContent = 'Pick a value between ' + min + ' and ' + max + '.';
    step.body.appendChild(hint);
    step.body.appendChild(document.createElement('br'));
    for (var n = min; n <= max; n++) {
      (function(v) {
        step.body.appendChild(btn(String(v), function() { commit(v); }));
      })(n);
    }
  }

  // --- Step 4: Defense -----------------------------------------------------
  function chooseDefense(stubId) {
    var c = cfg(stubId);
    var defs = c.state.target.defenses || [];
    var step = appendStep(stubId, 'Select Defense (' + escapeHtml(c.state.target.name) + ')', 'defense');
    var pick = function(d) {
      c.state.defense = d;
      lockStep(step, 'Defense: <strong>' + escapeHtml(d.label) + '</strong>');
      chooseDefenseDice(stubId);
    };
    if (defs.length === 0) { step.body.textContent = 'No defenses available.'; return; }
    if (defs.length === 1) { pick(defs[0]); return; }
    defs.forEach(function(d) {
      step.body.appendChild(btn(escapeHtml(d.label), function() { pick(d); }));
    });
  }

  // --- Step 4b: Defense dice (only if defense uses dice) ------------------
  function chooseDefenseDice(stubId) {
    var c = cfg(stubId);
    var d = c.state.defense;
    if (!d || !d.uses_dice) { chooseAllyReactions(stubId); return; }
    var min = d.min_dice | 0;
    var max = d.max_dice | 0;
    var step = appendStep(stubId, 'Defense Dice (' + min + '–' + max + ')', 'defenseDice');
    if (max < min) {
      step.body.textContent = 'Cannot afford defense; no dice available.';
      chooseAllyReactions(stubId);
      return;
    }
    var commit = function(n) {
      c.state.defenseDice = n;
      lockStep(step, 'Defense dice: <strong>' + n + '</strong>');
      chooseAllyReactions(stubId);
    };
    if (min === max) { commit(min); return; }
    for (var n = min; n <= max; n++) {
      (function(v) {
        step.body.appendChild(btn(String(v), function() { commit(v); }));
      })(n);
    }
  }

  // --- Step 5: Ally reactions ---------------------------------------------
  function chooseAllyReactions(stubId) {
    var c = cfg(stubId);
    var allies = c.allyReactions || [];
    if (allies.length === 0) { rollAttack(stubId); return; }
    var step = appendStep(stubId, 'Ally Reactions', 'allyReactions');
    var picks = [];
    allies.forEach(function(a) {
      var b = btn(escapeHtml(a.label), function() {
        if (b.classList.toggle('melee-btn-selected')) {
          picks.push(a);
        } else {
          var i = picks.indexOf(a);
          if (i !== -1) picks.splice(i, 1);
        }
      });
      step.body.appendChild(b);
    });
    var done = btn('Continue', function() {
      c.state.allyReactions = picks.slice();
      var summary = picks.length === 0
        ? '<em>No ally reactions.</em>'
        : 'Ally reactions: <strong>' + picks.map(function(a){ return escapeHtml(a.label); }).join(', ') + '</strong>';
      lockStep(step, summary);
      rollAttack(stubId);
    }, 'melee-btn-primary');
    step.body.appendChild(document.createElement('br'));
    step.body.appendChild(done);
  }

  // --- Step 6: Roll attack (and any rolled defense / ally rolls) ----------
  function rollAttack(stubId) {
    var c = cfg(stubId);
    var w = c.state.weapon;
    var def = c.state.defense;
    var isFlatfooted = !def || def.kind === 'nothing';
    var tn = attackTn(stubId, w, def, isFlatfooted);
    var step = appendStep(stubId, 'Attack Roll');
    var hint = document.createElement('div');
    hint.className = 'melee-meta';
    hint.textContent = c.state.attackDice + ' dice @ TN ' + tn;
    step.body.appendChild(hint);
    var slot = document.createElement('div');
    slot.className = 'melee-roll-slot';
    step.body.appendChild(slot);
    fetchRollPartial({
      check_name: c.attacker.skill.name + ' (' + w.name + ')',
      dice_count: c.state.attackDice,
      tn: tn,
      starting_value: 0
    }).then(function(html) {
      injectHtmlWithScripts(slot, html);
      slot.addEventListener('rollstub:confirm', function onConfirm(e) {
        slot.removeEventListener('rollstub:confirm', onConfirm);
        c.state.attackSuccesses = parseInt(e.detail.value, 10) || 0;
        lockStep(step, 'Attack: <strong>' + c.state.attackSuccesses + '</strong> successes' +
          ' <span class="melee-meta">(' + c.state.attackDice + ' dice @ TN ' + tn + ')</span>');
        rollDefense(stubId);
      });
    });
  }

  function rollDefense(stubId) {
    var c = cfg(stubId);
    var def = c.state.defense;
    if (!def || !def.uses_dice || c.state.defenseDice <= 0) {
      rollAllyReactions(stubId, 0);
      return;
    }
    var tn = defenseTn(stubId, c.state.weapon, def);
    var step = appendStep(stubId, def.label + ' Roll');
    var hint = document.createElement('div');
    hint.className = 'melee-meta';
    hint.textContent = c.state.defenseDice + ' dice @ TN ' + tn;
    step.body.appendChild(hint);
    var slot = document.createElement('div');
    slot.className = 'melee-roll-slot';
    step.body.appendChild(slot);
    fetchRollPartial({
      check_name: def.label,
      dice_count: c.state.defenseDice,
      tn: tn,
      starting_value: 0
    }).then(function(html) {
      injectHtmlWithScripts(slot, html);
      slot.addEventListener('rollstub:confirm', function onConfirm(e) {
        slot.removeEventListener('rollstub:confirm', onConfirm);
        c.state.defenseSuccesses = parseInt(e.detail.value, 10) || 0;
        lockStep(step, def.label + ': <strong>' + c.state.defenseSuccesses + '</strong> successes' +
          ' <span class="melee-meta">(' + c.state.defenseDice + ' dice @ TN ' + tn + ')</span>');
        rollAllyReactions(stubId, 0);
      });
    });
  }

  // Sequentially roll any selected ally reactions that supply skill+dice.
  function rollAllyReactions(stubId, idx) {
    var c = cfg(stubId);
    var queue = c.state.allyReactions.filter(function(a) { return a.skill && a.max_dice; });
    if (idx >= queue.length) { chooseTargetReactions(stubId); return; }
    var a = queue[idx];
    var w = c.state.weapon;
    var tn = c.baseTn - (a.skill.bonus | 0) + (w.attack_bonus | 0);
    var dice = a.max_dice | 0;
    var step = appendStep(stubId, a.label);
    var slot = document.createElement('div');
    slot.className = 'melee-roll-slot';
    step.body.appendChild(slot);
    fetchRollPartial({
      check_name: a.label, dice_count: dice, tn: tn, starting_value: 0
    }).then(function(html) {
      injectHtmlWithScripts(slot, html);
      slot.addEventListener('rollstub:confirm', function onConfirm(e) {
        slot.removeEventListener('rollstub:confirm', onConfirm);
        var s = parseInt(e.detail.value, 10) || 0;
        c.state.allyResults.push({key: a.key, label: a.label, successes: s, dice: dice, tn: tn});
        lockStep(step, escapeHtml(a.label) + ': <strong>' + s + '</strong> successes');
        rollAllyReactions(stubId, idx + 1);
      });
    });
  }

  // --- Step 7: Target reactions -------------------------------------------
  function chooseTargetReactions(stubId) {
    var c = cfg(stubId);
    var reactions = (c.state.target && c.state.target.reactions) || [];
    if (reactions.length === 0) { collectDamage(stubId); return; }
    var step = appendStep(stubId, 'Target Reactions', 'targetReactions');
    var picks = [];
    reactions.forEach(function(r) {
      var label = escapeHtml(r.label) + (r.cost ? ' <span class="melee-meta">(' + escapeHtml(r.cost) + ')</span>' : '');
      var b = btn(label, function() {
        if (b.classList.toggle('melee-btn-selected')) picks.push(r);
        else {
          var i = picks.indexOf(r);
          if (i !== -1) picks.splice(i, 1);
        }
      });
      step.body.appendChild(b);
    });
    var done = btn('Continue', function() {
      c.state.targetReactions = picks.slice();
      var summary = picks.length === 0
        ? '<em>No target reactions.</em>'
        : 'Target reactions: <strong>' + picks.map(function(r){ return escapeHtml(r.label); }).join(', ') + '</strong>';
      lockStep(step, summary);
      collectDamage(stubId);
    }, 'melee-btn-primary');
    step.body.appendChild(document.createElement('br'));
    step.body.appendChild(done);
  }

  // --- Step 8: Damage form -------------------------------------------------
  function collectDamage(stubId) {
    var c = cfg(stubId);
    var w = c.state.weapon;
    var atk = c.state.attackSuccesses | 0;
    var defS = c.state.defenseSuccesses | 0;
    var allyBlock = c.state.allyResults.reduce(function(s, r) { return s + (r.successes|0); }, 0);
    var net = atk - defS - allyBlock;
    var defaultDmg = Math.max(0, (w.damage|0) + net);
    var defaultBleed = Math.max(0, w.bleed|0);
    var defaultThreshold = w.threshold|0;
    var step = appendStep(stubId, 'Confirm Damage', 'damage');
    var meta = document.createElement('div');
    meta.className = 'melee-meta';
    meta.innerHTML = 'Net successes: <strong>' + net + '</strong> ' +
      '(' + atk + ' attack &minus; ' + defS + ' defense' +
      (allyBlock > 0 ? ' &minus; ' + allyBlock + ' ally block' : '') + ')';
    step.body.appendChild(meta);

    var form = document.createElement('div');
    form.className = 'melee-damage-form';
    form.innerHTML =
      '<label>Damage <input type="number" min="0" value="' + defaultDmg + '" data-field="damage"></label>' +
      '<label>Bleed <input type="number" min="0" value="' + defaultBleed + '" data-field="bleed"></label>' +
      '<label>Threshold <input type="number" min="0" value="' + defaultThreshold + '" data-field="threshold"></label>' +
      '<label>Afflictions <input type="text" placeholder="e.g. poison:2, paralysis:1" data-field="afflictions"></label>';
    step.body.appendChild(form);

    var submit = btn('Submit', function() {
      var damage = parseInt(form.querySelector('[data-field="damage"]').value, 10) || 0;
      var bleed = parseInt(form.querySelector('[data-field="bleed"]').value, 10) || 0;
      var threshold = parseInt(form.querySelector('[data-field="threshold"]').value, 10) || 0;
      var raw = form.querySelector('[data-field="afflictions"]').value || '';
      var afflictions = raw.split(',').map(function(t){return t.trim();}).filter(Boolean).map(function(t){
        var p = t.split(':');
        return {key: (p[0]||'').trim(), value: parseInt((p[1]||'0').trim(), 10) || 0};
      });
      c.state.damage = damage;
      c.state.bleed = bleed;
      c.state.threshold = threshold;
      c.state.afflictions = afflictions;

      var summary = '<strong>Damage:</strong> ' + damage +
        ' &nbsp; <strong>Bleed:</strong> ' + bleed +
        ' &nbsp; <strong>Threshold:</strong> ' + threshold;
      if (afflictions.length > 0) {
        summary += '<br><strong>Afflictions:</strong> ' +
          afflictions.map(function(a){ return escapeHtml(a.key) + ' ' + a.value; }).join(', ');
      }
      lockStep(step, summary);

      var detail = {
        target: c.state.target,
        weapon: c.state.weapon,
        attackDice: c.state.attackDice,
        defense: c.state.defense,
        defenseDice: c.state.defenseDice,
        allyReactions: c.state.allyReactions,
        allyResults: c.state.allyResults,
        attackSuccesses: c.state.attackSuccesses,
        defenseSuccesses: c.state.defenseSuccesses,
        targetReactions: c.state.targetReactions,
        damage: damage,
        bleed: bleed,
        threshold: threshold,
        afflictions: afflictions
      };
      var root = rootEl(stubId);
      if (root) {
        root.dispatchEvent(new CustomEvent('meleeattack:confirm', {
          bubbles: true, detail: detail
        }));
      }
    }, 'melee-btn-primary');
    step.body.appendChild(submit);
  }

  // The partial calls window.meleeAttackInit(stubId) inline once its
  // config is registered. If this script hasn't loaded yet (script tag
  // is at the bottom of the layout, but the partial's <script> runs
  // mid-body), the inline call no-ops; this DOMContentLoaded handler
  // catches up and starts every registered stub that isn't running yet.
  window.meleeAttackInit = function(stubId) {
    var c = cfg(stubId);
    if (!c || c._started) return;
    c._started = true;
    start(stubId);
  };

  function bootAll() {
    var configs = window.meleeAttackConfigs || {};
    Object.keys(configs).forEach(function(id) { window.meleeAttackInit(id); });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootAll);
  } else {
    bootAll();
  }
})();
