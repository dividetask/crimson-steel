// Compendium Spell List filters (docs/common/ui/abilities_spell_list_stub.md).
// Purely local filtering of the rendered rows by School / Tier / Skill; the
// Spell list never refetches. Clicking a Spell name opens its detail popup
// (handled by app.js's .cs-spell-link delegation).

const root = document.querySelector('[data-spell-list]');
if (root) initSpellList(root);

function initSpellList(root) {
  const selects = {
    school: root.querySelector('[data-filter="school"]'),
    tier: root.querySelector('[data-filter="tier"]'),
    skill: root.querySelector('[data-filter="skill"]'),
  };
  const clearBtn = root.querySelector('[data-filter-clear]');
  const rows = Array.from(root.querySelectorAll('.spell-row'));
  const emptyMsg = root.querySelector('[data-empty]');

  function apply() {
    const school = selects.school.value;
    const tier = selects.tier.value;
    const skill = selects.skill.value;
    let shown = 0;
    rows.forEach((row) => {
      const tiers = (row.dataset.tiers || '').split(',').filter(Boolean);
      const skills = (row.dataset.skills || '').split(',').filter(Boolean);
      const match =
        (!school || row.dataset.school === school) &&
        (!tier || tiers.includes(tier)) &&
        (!skill || skills.includes(skill));
      row.hidden = !match;
      if (match) shown += 1;
    });
    if (emptyMsg) emptyMsg.hidden = shown !== 0;
  }

  Object.values(selects).forEach((sel) => sel && sel.addEventListener('change', apply));
  if (clearBtn) {
    clearBtn.addEventListener('click', () => {
      Object.values(selects).forEach((sel) => { if (sel) sel.value = ''; });
      apply();
    });
  }
  apply();
}
