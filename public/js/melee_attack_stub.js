// Client-side state machine driving the melee_attack_stub flow.
//
// The Ruby helper renders an empty container and ships the stub config
// (attacker, targets, ally reactions, dice rules) on window.meleeAttackConfigs
// keyed by stub id. This file picks the config up at init time, walks the
// DM through the steps below, and dispatches `meleeattack:confirm` on the
// stub root with the full chosen payload at the end.
//
// Steps with a single (or zero) option auto-advance. Reaction steps
// with no options are skipped entirely. The single Rolls step embeds
// the multi_roll_stub partial via /multi_roll_stub/render and waits
// for its `multiroll:confirm` event to capture per-row successes.
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
  // Per-ally luck steps use 'allyLuck-<idx>' so the dispatcher can
  // dive back to the right ally when the user clicks Change.
  function rollbackHandler(kind) {
    var staticHandlers = {
      target:          chooseTarget,
      weapon:          chooseWeapon,
      attackDice:      chooseAttackDice,
      attackLuck:      chooseAttackLuck,
      defense:         chooseDefense,
      defenseDice:     chooseDefenseDice,
      defenseLuck:     chooseDefenseLuck,
      allyReactions:   chooseAllyReactions,
      targetReactions: chooseTargetReactions,
      damage:          collectDamage
    };
    if (staticHandlers[kind]) return staticHandlers[kind];
    if (kind.indexOf('allyDice-') === 0) {
      var diceIdx = parseInt(kind.substring('allyDice-'.length), 10);
      return function(stubId) { chooseAllyDices(stubId, diceIdx); };
    }
    if (kind.indexOf('allyLuck-') === 0) {
      var luckIdx = parseInt(kind.substring('allyLuck-'.length), 10);
      return function(stubId) { chooseAllyLucks(stubId, luckIdx); };
    }
    return null;
  }

  // Shared luck prompt. For each configured luck source we render one
  // button per remaining point (e.g. 4 buttons for "+1..+4" Bardic, 3
  // for "-1..-3" Unsettling). Selecting a button on any source clears
  // the others -- a roll can carry bonus luck or penalty luck, never
  // both. Click the same button again to deselect. Skips entirely
  // when no luck sources are configured. Labels and remaining come
  // from the data; nothing here is hardcoded.
  function promptLuck(stubId, kind, title, defaults, onContinue) {
    var c = cfg(stubId);
    var sources = c.luckSources || [];
    if (sources.length === 0) { onContinue({}); return; }
    var step = appendStep(stubId, title, kind);
    // Mutually-exclusive selection: at most one entry across all sources.
    var selected = {};
    if (defaults) {
      var seedKey = Object.keys(defaults).find(function(k) { return defaults[k] > 0; });
      if (seedKey) selected[seedKey] = defaults[seedKey];
    }
    var btnsByKey = {};
    sources.forEach(function(src) {
      var remaining = src.remaining | 0;
      if (remaining <= 0) return;
      var row = document.createElement('div');
      row.className = 'melee-luck-row';
      var label = document.createElement('span');
      label.className = 'melee-luck-row-label';
      label.innerHTML = '<strong>' + escapeHtml(src.label) + '</strong>:';
      row.appendChild(label);
      var sign = src.kind === 'penalty' ? '-' : '+';
      var entries = [];
      btnsByKey[src.key] = entries;
      for (var i = 1; i <= remaining; i++) {
        (function(amount) {
          var b = document.createElement('button');
          b.type = 'button';
          b.className = 'melee-btn melee-luck-pt';
          if (src.kind === 'penalty') b.classList.add('melee-luck-pt-penalty');
          b.textContent = sign + amount;
          b.addEventListener('click', function() {
            if (selected[src.key] === amount) {
              delete selected[src.key];
            } else {
              selected = {};
              selected[src.key] = amount;
            }
            paint();
          });
          row.appendChild(b);
          entries.push({btn: b, amount: amount});
        })(i);
      }
      step.body.appendChild(row);
    });
    function paint() {
      Object.keys(btnsByKey).forEach(function(key) {
        btnsByKey[key].forEach(function(item) {
          item.btn.classList.toggle('melee-luck-pt-selected', selected[key] === item.amount);
        });
      });
    }
    paint();
    var done = btn('Continue', function() {
      var chosen = {};
      Object.keys(selected).forEach(function(k) {
        if (selected[k] > 0) chosen[k] = selected[k];
      });
      var pickedKeys = Object.keys(chosen);
      var summary;
      if (pickedKeys.length === 0) {
        summary = '<em>No luck spent.</em>';
      } else {
        summary = pickedKeys.map(function(k) {
          var src = sources.filter(function(s) { return s.key === k; })[0];
          var sign = src && src.kind === 'penalty' ? '-' : '+';
          return '<strong>' + escapeHtml(src.label) + ':</strong> ' + sign + chosen[k];
        }).join(', ');
      }
      lockStep(step, summary);
      onContinue(chosen);
    }, 'melee-btn-primary');
    step.body.appendChild(done);
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

  function fetchMultiRollPartial(params) {
    return postFormText('/multi_roll_stub/render', params);
  }

  function postFormText(url, params) {
    var body = new URLSearchParams();
    Object.keys(params).forEach(function(k) {
      if (params[k] !== undefined && params[k] !== null) body.append(k, params[k]);
    });
    return fetch(url, {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body.toString()
    }).then(function(r) {
      if (!r.ok) throw new Error(url + ' failed: ' + r.status);
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
      attackLuck: {},
      defense: null, defenseDice: 0,
      defenseLuck: {},
      allyReactions: [], allyLucks: [], allyResults: [],
      attackSuccesses: 0, defenseSuccesses: 0,
      targetReactions: [],
      damage: 0, threshold: 0, afflictions: []
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
      chooseAttackLuck(stubId);
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

  // --- Step 3b: Luck for attack roll --------------------------------------
  function chooseAttackLuck(stubId) {
    var c = cfg(stubId);
    promptLuck(stubId, 'attackLuck', 'Luck for Attack',
      c.state.attackLuck, function(chosen) {
        c.state.attackLuck = chosen;
        chooseDefense(stubId);
      });
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
      chooseDefenseLuck(stubId);
    };
    if (min === max) { commit(min); return; }
    for (var n = min; n <= max; n++) {
      (function(v) {
        step.body.appendChild(btn(String(v), function() { commit(v); }));
      })(n);
    }
  }

  // --- Step 4c: Luck for defense roll -------------------------------------
  function chooseDefenseLuck(stubId) {
    var c = cfg(stubId);
    promptLuck(stubId, 'defenseLuck', 'Luck for ' + c.state.defense.label,
      c.state.defenseLuck, function(chosen) {
        c.state.defenseLuck = chosen;
        chooseAllyReactions(stubId);
      });
  }

  // --- Step 5: Ally reactions ---------------------------------------------
  function chooseAllyReactions(stubId) {
    var c = cfg(stubId);
    var allies = c.allyReactions || [];
    if (allies.length === 0) { rollsPanel(stubId); return; }
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
      // Reset per-ally dice / luck since the ally list just changed;
      // the ally dice and ally luck steps will repopulate as they fire.
      c.state.allyDices = [];
      c.state.allyLucks = [];
      var summary = picks.length === 0
        ? '<em>No ally reactions.</em>'
        : 'Ally reactions: <strong>' + picks.map(function(a){ return escapeHtml(a.label); }).join(', ') + '</strong>';
      lockStep(step, summary);
      chooseAllyDices(stubId, 0);
    }, 'melee-btn-primary');
    step.body.appendChild(document.createElement('br'));
    step.body.appendChild(done);
  }

  // --- Step 5b: Dice per rolled ally reaction -----------------------------
  // Most ally reactions (Shield of Faith, Healing Word, etc.) cost
  // dice; a few (Bardic Inspiration, pure rerolls) do not. Walk the
  // selected reactions and prompt for a dice count on the ones that
  // carry skill + max_dice; allies without those are passed through.
  function chooseAllyDices(stubId, idx) {
    var c = cfg(stubId);
    var allies = (c.state.allyReactions || []).filter(function(a) {
      return a.skill && (a.max_dice | 0) > 0;
    });
    if (idx >= allies.length) { chooseAllyLucks(stubId, 0); return; }
    var ally = allies[idx];
    var min = ally.min_dice | 0;
    var max = ally.max_dice | 0;
    var step = appendStep(stubId, 'Dice for ' + ally.label + ' (' + min + '–' + max + ')',
                          'allyDice-' + idx);
    if (max < min) {
      step.body.textContent = 'Cannot afford this reaction.';
      chooseAllyDices(stubId, idx + 1);
      return;
    }
    c.state.allyDices = c.state.allyDices || [];
    var commit = function(n) {
      c.state.allyDices[idx] = n;
      lockStep(step, 'Dice: <strong>' + n + '</strong>');
      chooseAllyDices(stubId, idx + 1);
    };
    if (min === max) { commit(min); return; }
    for (var n = min; n <= max; n++) {
      (function(v) {
        step.body.appendChild(btn(String(v), function() { commit(v); }));
      })(n);
    }
  }

  // --- Step 5c: Luck per rolled ally reaction -----------------------------
  // Walks the selected ally reactions and asks for luck on any that
  // roll dice. Allies without skill+dice (pure rerolls etc.) skip.
  function chooseAllyLucks(stubId, idx) {
    var c = cfg(stubId);
    var allies = (c.state.allyReactions || []).filter(function(a) {
      return a.skill && (a.max_dice | 0) > 0;
    });
    if (idx >= allies.length) { rollsPanel(stubId); return; }
    var ally = allies[idx];
    c.state.allyLucks = c.state.allyLucks || [];
    promptLuck(stubId, 'allyLuck-' + idx, 'Luck for ' + ally.label,
      c.state.allyLucks[idx], function(chosen) {
        c.state.allyLucks[idx] = chosen;
        chooseAllyLucks(stubId, idx + 1);
      });
  }

  // --- Step 6: All rolls in one panel -------------------------------------
  // Builds the row list (attack + optional defense + each rolled ally
  // reaction), pulls a fresh multi_roll_stub partial, and waits for
  // the panel's `multiroll:confirm` event to capture per-row successes.
  // Each row gets its luck/unsettling buttons populated from the
  // chosen luck amounts; labels come from luckSources -- never
  // hardcoded.
  function rollsPanel(stubId) {
    var c = cfg(stubId);
    var w = c.state.weapon;
    var def = c.state.defense;
    var isFlatfooted = !def || def.kind === 'nothing';

    // Pull the first bonus and first penalty source for label/amount.
    // Configs with multiple bonus or penalty sources still work; only
    // the first of each kind is wired through to the per-row buttons.
    var bonusSrc = null, penaltySrc = null;
    (c.luckSources || []).forEach(function(s) {
      if (!bonusSrc && s.kind === 'bonus') bonusSrc = s;
      else if (!penaltySrc && s.kind === 'penalty') penaltySrc = s;
    });
    function rowLuck(chosen) {
      chosen = chosen || {};
      return {
        luck_amount:        bonusSrc   ? (chosen[bonusSrc.key]   | 0) : 0,
        luck_label:         bonusSrc   ? bonusSrc.label   : '',
        unsettling_amount:  penaltySrc ? (chosen[penaltySrc.key] | 0) : 0,
        unsettling_label:   penaltySrc ? penaltySrc.label : ''
      };
    }

    var rolls = [];
    var atkLuck = rowLuck(c.state.attackLuck);
    rolls.push(Object.assign({
      key:            'attack',
      label:          c.attacker.skill.name + ' (' + w.name + ')',
      dice_count:     c.state.attackDice,
      tn:             attackTn(stubId, w, def, isFlatfooted),
      starting_value: 0
    }, atkLuck));

    if (def && def.uses_dice && c.state.defenseDice > 0) {
      var defLuck = rowLuck(c.state.defenseLuck);
      rolls.push(Object.assign({
        key:            'defense',
        label:          def.label,
        dice_count:     c.state.defenseDice,
        tn:             defenseTn(stubId, w, def),
        starting_value: 0
      }, defLuck));
    }

    var allies = (c.state.allyReactions || []).filter(function(a) {
      return a.skill && (a.max_dice | 0) > 0;
    });
    allies.forEach(function(a, idx) {
      var tn = c.baseTn - (a.skill.bonus | 0) + (w.attack_bonus | 0);
      var allyLuck = rowLuck((c.state.allyLucks || [])[idx]);
      var diceCount = ((c.state.allyDices || [])[idx] | 0) || (a.max_dice | 0);
      rolls.push(Object.assign({
        key:            'ally-' + idx,
        label:          a.label,
        dice_count:     diceCount,
        tn:             tn,
        starting_value: 0
      }, allyLuck));
    });

    var step = appendStep(stubId, 'Rolls');
    var slot = document.createElement('div');
    slot.className = 'melee-roll-slot';
    step.body.appendChild(slot);

    fetchMultiRollPartial({
      rolls: JSON.stringify(rolls),
      title: 'Rolls'
    }).then(function(html) {
      injectHtmlWithScripts(slot, html);
      slot.addEventListener('multiroll:confirm', function onConfirm(e) {
        slot.removeEventListener('multiroll:confirm', onConfirm);
        c.state.attackSuccesses = 0;
        c.state.defenseSuccesses = 0;
        c.state.allyResults = [];
        e.detail.rows.forEach(function(r) {
          if (r.key === 'attack') {
            c.state.attackSuccesses = r.successes | 0;
          } else if (r.key === 'defense') {
            c.state.defenseSuccesses = r.successes | 0;
          } else if (r.key.indexOf('ally-') === 0) {
            var i = parseInt(r.key.substring(5), 10);
            c.state.allyResults[i] = {
              label: r.label, successes: r.successes | 0,
              dice: r.diceCount, tn: r.tn
            };
          }
        });
        var allyBlock = c.state.allyResults.reduce(function(s, x) {
          return s + (x ? (x.successes | 0) : 0);
        }, 0);
        var summary = document.createElement('div');
        summary.className = 'melee-step-summary';
        var bits = ['Attack: <strong>' + c.state.attackSuccesses + '</strong>'];
        if (def && def.uses_dice) bits.push('Defense: <strong>' + c.state.defenseSuccesses + '</strong>');
        if (allyBlock > 0) bits.push('Ally block: <strong>' + allyBlock + '</strong>');
        summary.innerHTML = bits.join(' &nbsp; ');
        step.body.appendChild(summary);
        chooseTargetReactions(stubId);
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
    var defaultThreshold = w.threshold|0;
    // Only afflictions the attack can already inflict (weapon + attacker
    // abilities) are surfaced -- no freeform input. The DM zeroes out
    // any line that should not actually trigger this swing.
    var weaponAfflictions = (w.afflictions || []).slice();

    var step = appendStep(stubId, 'Confirm Damage', 'damage');
    var meta = document.createElement('div');
    meta.className = 'melee-meta';
    meta.innerHTML = 'Net successes: <strong>' + net + '</strong> ' +
      '(' + atk + ' attack &minus; ' + defS + ' defense' +
      (allyBlock > 0 ? ' &minus; ' + allyBlock + ' ally block' : '') + ')';
    step.body.appendChild(meta);

    var form = document.createElement('div');
    form.className = 'melee-damage-form';
    var html =
      '<label>Damage <input type="number" min="0" value="' + defaultDmg + '" data-field="damage"></label>' +
      '<label>Threshold <input type="number" min="0" value="' + defaultThreshold + '" data-field="threshold"></label>';
    if (weaponAfflictions.length > 0) {
      html += '<div class="melee-affliction-list">' +
        '<div class="melee-meta">Afflictions inflicted by this attack:</div>';
      weaponAfflictions.forEach(function(a) {
        html += '<label>' + escapeHtml(a.label) + ' ' +
          '<input type="number" min="0" value="' + (a.amount|0) + '" ' +
          'data-affliction-key="' + escapeHtml(a.key) + '" ' +
          'data-affliction-label="' + escapeHtml(a.label) + '"></label>';
      });
      html += '</div>';
    }
    form.innerHTML = html;
    step.body.appendChild(form);

    var submit = btn('Submit', function() {
      var damage = parseInt(form.querySelector('[data-field="damage"]').value, 10) || 0;
      var threshold = parseInt(form.querySelector('[data-field="threshold"]').value, 10) || 0;
      var afflictions = Array.prototype.slice.call(
        form.querySelectorAll('[data-affliction-key]')
      ).map(function(el) {
        return {
          key:    el.dataset.afflictionKey,
          label:  el.dataset.afflictionLabel,
          amount: parseInt(el.value, 10) || 0
        };
      }).filter(function(a) { return a.amount > 0; });

      c.state.damage = damage;
      c.state.threshold = threshold;
      c.state.afflictions = afflictions;

      var summary = '<strong>Damage:</strong> ' + damage +
        ' &nbsp; <strong>Threshold:</strong> ' + threshold;
      if (afflictions.length > 0) {
        summary += '<br><strong>Afflictions:</strong> ' +
          afflictions.map(function(a){ return escapeHtml(a.label) + ' ' + a.amount; }).join(', ');
      }
      lockStep(step, summary);

      var detail = {
        target: c.state.target,
        weapon: c.state.weapon,
        attackDice: c.state.attackDice,
        attackLuck: c.state.attackLuck,
        defense: c.state.defense,
        defenseDice: c.state.defenseDice,
        defenseLuck: c.state.defenseLuck,
        allyReactions: c.state.allyReactions,
        allyLucks: c.state.allyLucks,
        allyResults: c.state.allyResults,
        attackSuccesses: c.state.attackSuccesses,
        defenseSuccesses: c.state.defenseSuccesses,
        targetReactions: c.state.targetReactions,
        damage: damage,
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
