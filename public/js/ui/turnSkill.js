import { renderCheckNet, logCheckRolls } from './checkRoll.js';

// Turn Action panel — Skill (out-of-combat only, DM Page).
//
// Pick a Skill (rolled at max dice), then — for an opposed Skill — multi-select
// target(s). The acting Character is the Supporting roll and each target an
// Opposing roll; the roll reuses the Check Resolution Stub (via /dm/skill_check)
// and the result shows the best-vs-worst pairings. Confirm logs every roll.
// Target selection uses the shared _creature_multiselect partial.
export class TurnSkill {
  static ensureLoaded(container) {
    if (!container || container.dataset.tskLoaded) return;
    container.dataset.tskLoaded = '1';
    container._actorId = parseInt(container.getAttribute('data-actor-id'), 10);
    container._targets = new Set();

    container.addEventListener('click', (e) => TurnSkill._onClick(container, e));
    container.addEventListener('change', (e) => {
      if (e.target.closest && e.target.closest('.result-input')) {
        renderCheckNet(container.querySelector('.ta-skill-result'), container.querySelector('.ta-skill-net'));
      }
    });

    container.innerHTML = '<p class="ta-attack-loading">Loading skills…</p>';
    fetch('/dm/skill_panel?actor_id=' + encodeURIComponent(container._actorId), { headers: { Accept: 'text/html' } })
      .then((r) => (r.ok ? r.text() : Promise.reject()))
      .then((html) => { container.innerHTML = html; })
      .catch(() => { container.innerHTML = '<p class="ta-warn">Could not load the skills.</p>'; });
  }

  static _onClick(container, e) {
    const t = e.target;
    const sk = t.closest && t.closest('.ta-sk-skill');
    if (sk && container.contains(sk)) { return TurnSkill._skill(container, sk); }
    const opt = t.closest && t.closest('.ms-opt');
    if (opt && container.contains(opt)) { return TurnSkill._toggle(container, opt); }
    if (t.closest && t.closest('.ta-sk-roll')) { return TurnSkill._roll(container); }
    if (t.closest && t.closest('.btn-confirm')) { setTimeout(() => logCheckRolls(container.querySelector('.ta-skill-result')), 0); }
  }

  static _skill(container, btn) {
    container._skill = btn.getAttribute('data-skill');
    container._targets.clear();
    container.querySelectorAll('.ta-sk-skill').forEach((b) => b.classList.toggle('cb-opt-selected', b === btn));
    container.querySelectorAll('.ms-opt').forEach((b) => b.classList.remove('cb-opt-selected'));
    const targets = container.querySelector('.ta-sk-targets');
    if (targets) targets.hidden = !btn.getAttribute('data-opposed');
    const roll = container.querySelector('.ta-sk-roll');
    if (roll) roll.hidden = false;
    const res = container.querySelector('.ta-skill-result');
    if (res) res.innerHTML = '';
  }

  static _toggle(container, btn) {
    const id = btn.getAttribute('data-id');
    if (container._targets.has(id)) { container._targets.delete(id); btn.classList.remove('cb-opt-selected'); }
    else { container._targets.add(id); btn.classList.add('cb-opt-selected'); }
  }

  static _roll(container) {
    if (!container._skill) return;
    const res = container.querySelector('.ta-skill-result');
    if (!res) return;
    res.innerHTML = '<p class="ta-attack-loading">Loading roll…</p>';
    let q = 'actors[]=' + encodeURIComponent(container._actorId) + '&skill=' + encodeURIComponent(container._skill);
    container._targets.forEach((id) => { q += '&targets[]=' + encodeURIComponent(id); });
    fetch('/dm/skill_check?' + q, { headers: { Accept: 'text/html' } })
      .then((r) => (r.ok ? r.text() : Promise.reject()))
      .then((html) => { res.innerHTML = html + '<div class="ta-skill-net dm-mult-net" hidden></div>'; })
      .catch(() => { res.innerHTML = '<p class="ta-warn">Could not roll the skill.</p>'; });
  }
}
