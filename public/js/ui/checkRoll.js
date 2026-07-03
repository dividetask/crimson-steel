// Shared helpers for the opposed skill-check panels (the Multiple group action
// and the single-character Skill action). The rolling is the Check Resolution
// Stub (_check_stub); these only read its result cells.

// Read the creature-name cell's own text (excluding the .tn-tip tooltip span).
export function nameText(el) {
  let t = '';
  el.childNodes.forEach((n) => { if (n.nodeType === 3) t += n.textContent; });
  return t.trim() || el.textContent.trim();
}

// Best-vs-worst net readout: the worst Supporting roll vs the best Opposing
// (the hardest contest for the group) and the best Supporting vs the worst
// Opposing (the easiest), each netted as Supporting − Opposing. The net is
// signed — a lost contest reads negative (0 vs 4 → net -4). With no opposition
// it just lists each roller's result.
export function renderCheckNet(resultEl, netEl) {
  if (!resultEl || !netEl) return;
  const sup = []; const opp = [];
  resultEl.querySelectorAll('.roll-group').forEach((g) => {
    const inp = g.querySelector('.result-input'); if (!inp) return;
    const nameEl = g.querySelector('.creature-name');
    const entry = { name: nameEl ? nameText(nameEl) : '?', val: parseInt(inp.value, 10) || 0 };
    (g.dataset.side === 'opposing' ? opp : sup).push(entry);
  });
  if (!sup.length) return;
  if (!opp.length) {
    netEl.textContent = sup.map((s) => s.name + ' (' + s.val + ')').join(', ');
    netEl.hidden = false; return;
  }
  const pick = (arr, better) => arr.reduce((a, b) => (better(b.val, a.val) ? b : a));
  const worstSup = pick(sup, (x, y) => x < y);
  const bestSup = pick(sup, (x, y) => x > y);
  const bestOpp = pick(opp, (x, y) => x > y);
  const worstOpp = pick(opp, (x, y) => x < y);
  const line = (s, o) => s.name + ' (' + s.val + ') vs ' + o.name + ' (' + o.val + ') net ' + (s.val - o.val);
  const hardest = line(worstSup, bestOpp);
  const easiest = line(bestSup, worstOpp);
  netEl.textContent = hardest === easiest ? hardest : (hardest + ', ' + easiest);
  netEl.hidden = false;
}

// POST every rolled side to the Roll Log (sequentially, so their writes don't
// race the shared store). Uses the dice RollController stashed on each group.
export function logCheckRolls(resultEl) {
  const payloads = [];
  resultEl.querySelectorAll('.roll-group').forEach((g) => {
    if (!g.dataset.rolledDice) return;
    let cfg = {}; let dice = [];
    try { cfg = JSON.parse(g.dataset.config); } catch (e) { /* defaults */ }
    try { dice = JSON.parse(g.dataset.rolledDice); } catch (e) { /* none */ }
    const inputs = g.querySelectorAll('.result-input');
    const nameEl = g.querySelector('.creature-name');
    const rollNameEl = g.querySelector('.roll-name');
    payloads.push({
      creature_name: nameEl ? nameText(nameEl) : '',
      roll_name: rollNameEl ? rollNameEl.textContent.replace(/[()]/g, '').trim() : '',
      tn: cfg.tn, base_tn: cfg.base_tn, bonus_penalty_list: cfg.bonus_penalty_list,
      dice_count: cfg.dice_count, starting_value: cfg.starting_value, dice,
      dois: inputs[0] ? parseInt(inputs[0].value, 10) || 0 : 0,
      critical_count: inputs[1] ? parseInt(inputs[1].value, 10) || 0 : 0
    });
  });
  payloads.reduce((chain, body) => chain.then(() => fetch('/dm/roll', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
  }).catch(function () {})), Promise.resolve());
}
