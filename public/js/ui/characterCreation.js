// Character Creation Stub controller.
//
// Drives the multi-step "New Character" wizard. All catalog data
// (attribute allocation rules, races, classes, per-class skill groups
// and spell-selection rules) is emitted into #cc-data by the server;
// this controller renders each step from it and POSTs the assembled
// character back to /character-creation on the final Confirm.
//
// Steps: Attributes → Race → Class → Skills → [Spells] → Confirm.
// The Spells step is present only when the chosen Class declares a
// spell-selection rule (count / points / domain).

const STEP_LABELS = {
  attributes: 'Attributes',
  race: 'Race',
  class: 'Class',
  skills: 'Skills',
  spells: 'Spells',
  confirm: 'Confirm'
};

function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  if (attrs) {
    for (const key in attrs) {
      const val = attrs[key];
      if (key === 'class') node.className = val;
      else if (key === 'text') node.textContent = val;
      else if (key === 'html') node.innerHTML = val;
      else if (key.startsWith('on') && typeof val === 'function') {
        node.addEventListener(key.slice(2), val);
      } else if (val === true) node.setAttribute(key, '');
      else if (val !== false && val != null) node.setAttribute(key, val);
    }
  }
  children.flat().forEach((child) => {
    if (child == null || child === false) return;
    node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  });
  return node;
}

function slug(text) {
  return String(text || '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function fmtNum(n) {
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

class CharacterCreator {
  constructor(root, blob) {
    this.root = root;
    this.blob = blob;
    this.alloc = blob.attribute_allocation;

    this.stepsEl = root.querySelector('[data-cc-steps]');
    this.stageEl = root.querySelector('[data-cc-stage]');
    this.errorEl = root.querySelector('[data-cc-error]');
    this.backBtn = root.querySelector('[data-cc-back]');
    this.nextBtn = root.querySelector('[data-cc-next]');

    this.state = {
      stepIndex: 0,
      attrs: {},
      raceKey: null,
      classKey: null,
      skills: {},      // catalog key -> selected (bool)
      setSuffix: {},   // set-skill key -> instance suffix text
      spells: {},      // spell catalog name -> selected (bool)
      deity: null,
      domains: [],
      name: '',
      player: ''
    };
    blob.attributes.forEach((k) => { this.state.attrs[k] = this.alloc.starting; });

    this.backBtn.addEventListener('click', () => this.goBack());
    this.nextBtn.addEventListener('click', () => this.goNext());

    this.render();
  }

  // ---- step model ---------------------------------------------------

  steps() {
    const list = ['attributes', 'race', 'class', 'skills'];
    const cls = this.currentClass();
    if (cls && cls.spell_selection) list.push('spells');
    list.push('confirm');
    return list;
  }

  currentStep() {
    const steps = this.steps();
    if (this.state.stepIndex >= steps.length) this.state.stepIndex = steps.length - 1;
    return steps[this.state.stepIndex];
  }

  currentRace() {
    return this.blob.races.find((r) => r.key === this.state.raceKey) || null;
  }

  currentClass() {
    return this.blob.classes.find((c) => c.key === this.state.classKey) || null;
  }

  // ---- attribute math ----------------------------------------------

  costOf(value) {
    const c = this.alloc.cost[value];
    return c == null ? 0 : c;
  }

  spent() {
    return this.blob.attributes.reduce((sum, k) => sum + this.costOf(this.state.attrs[k]), 0);
  }

  remaining() {
    return this.alloc.pool - this.spent();
  }

  raceAdj(attr) {
    const race = this.currentRace();
    return race ? (race.adjustments[attr] || 0) : 0;
  }

  // Attribute as shown on the Race step: point-buy value + racial stat.
  shownAttr(attr) {
    return this.state.attrs[attr] + this.raceAdj(attr);
  }

  // Effective Intelligence for the Skill Pick formula (point-buy +
  // racial + the Tier inherent bonus), matching the saved Creature.
  pickCount() {
    const cls = this.currentClass();
    if (!cls) return 0;
    const effInt = this.state.attrs.int + this.raceAdj('int') + (this.blob.inherent_bonus || 0);
    return Math.floor(effInt / 4) + cls.bonus_skills;
  }

  // ---- skill / spell collection ------------------------------------

  checkedSkills() {
    return Object.keys(this.state.skills).filter((k) => this.state.skills[k]);
  }

  skillsComplete() {
    return this.checkedSkills().every((k) => !k.endsWith('_') || slug(this.state.setSuffix[k]) !== '');
  }

  collectSkills() {
    const out = [];
    this.checkedSkills().forEach((key) => {
      if (key.endsWith('_')) {
        const suffix = slug(this.state.setSuffix[key]);
        if (suffix) out.push(key + suffix);
      } else {
        out.push(key);
      }
    });
    return out;
  }

  checkedSpells() {
    return Object.keys(this.state.spells).filter((k) => this.state.spells[k]);
  }

  spellSpent() {
    const cls = this.currentClass();
    const pool = cls.spell_selection.spells || [];
    return this.checkedSpells().reduce((sum, key) => {
      const sp = pool.find((p) => p.key === key);
      return sum + (sp ? sp.cost : 0);
    }, 0);
  }

  // ---- navigation ---------------------------------------------------

  canAdvance() {
    switch (this.currentStep()) {
      case 'attributes': return this.remaining() >= 0;
      case 'race': return !!this.state.raceKey;
      case 'class': return !!this.state.classKey;
      case 'skills': return this.checkedSkills().length === this.pickCount() && this.skillsComplete();
      case 'spells': return this.spellsValid();
      case 'confirm': return this.state.name.trim() !== '';
      default: return true;
    }
  }

  spellsValid() {
    const sel = this.currentClass().spell_selection;
    if (sel.mode === 'domain') {
      return !!this.state.deity && this.state.domains.length === this.requiredDomainCount(sel);
    }
    if (sel.mode === 'points') return this.spellSpent() <= sel.budget;
    return this.checkedSpells().length <= sel.budget; // count
  }

  // How many domains a Cleric of the chosen deity must pick: the
  // configured number, capped by how many favored domains the deity has.
  requiredDomainCount(sel) {
    const deity = sel.deities.find((d) => d.name === this.state.deity);
    if (!deity) return 0;
    return Math.min(sel.max_domains, deity.domains.length);
  }

  goBack() {
    if (this.state.stepIndex > 0) {
      this.state.stepIndex -= 1;
      this.render();
    }
  }

  goNext() {
    if (!this.canAdvance()) return;
    const steps = this.steps();
    if (this.state.stepIndex >= steps.length - 1) {
      this.create();
      return;
    }
    this.state.stepIndex += 1;
    this.render();
  }

  // ---- rendering ----------------------------------------------------

  render() {
    this.clearError();
    this.renderSteps();
    this.stageEl.innerHTML = '';
    const step = this.currentStep();
    // The running attribute totals (point-buy + racial) stay visible from
    // the Race step onward. On the Attributes step the editable grid is
    // the display, so the bar is omitted there to avoid duplication.
    this._attrBarEl = null;
    if (step !== 'attributes') this.stageEl.appendChild(this.buildAttributeBar());
    const builder = {
      attributes: () => this.buildAttributes(),
      race: () => this.buildRace(),
      class: () => this.buildClass(),
      skills: () => this.buildSkills(),
      spells: () => this.buildSpells(),
      confirm: () => this.buildConfirm()
    }[step];
    this.stageEl.appendChild(builder());
    this.refreshNav();
  }

  // Persistent attribute readout shown above every step after Attributes.
  // Values reflect the point-buy choices plus the selected Race's
  // modifiers; the per-attribute racial delta is shown as a chip.
  buildAttributeBar() {
    const bar = el('div', { class: 'cc-attr-bar' });
    this._attrBarEl = bar;
    this.refreshAttrBar();
    return bar;
  }

  refreshAttrBar() {
    const bar = this._attrBarEl;
    if (!bar) return;
    bar.innerHTML = '';
    bar.appendChild(el('span', { class: 'cc-attr-bar-label', text: 'Attributes' }));
    this.blob.attributes.forEach((attr) => {
      const adj = this.raceAdj(attr);
      const cell = el('span', { class: 'cc-attr-cell' },
        el('span', { class: 'cc-attr-cell-name', text: attr.toUpperCase() }),
        el('span', { class: 'cc-attr-cell-val', text: String(this.shownAttr(attr)) }));
      if (adj) {
        cell.appendChild(el('span', {
          class: 'cc-attr-cell-adj ' + (adj > 0 ? 'cc-pos' : 'cc-neg'),
          text: (adj > 0 ? '+' : '') + adj
        }));
      }
      bar.appendChild(cell);
    });
  }

  renderSteps() {
    const steps = this.steps();
    this.stepsEl.innerHTML = '';
    steps.forEach((id, i) => {
      let cls = 'cc-step';
      if (i === this.state.stepIndex) cls += ' cc-step-current';
      else if (i < this.state.stepIndex) cls += ' cc-step-done';
      this.stepsEl.appendChild(el('li', { class: cls },
        el('span', { class: 'cc-step-num', text: String(i + 1) }),
        el('span', { class: 'cc-step-label', text: STEP_LABELS[id] })));
    });
  }

  refreshNav() {
    const steps = this.steps();
    const last = this.state.stepIndex >= steps.length - 1;
    this.backBtn.hidden = this.state.stepIndex === 0;
    this.nextBtn.textContent = last ? 'Create Character' : 'Next ›';
    const ok = this.canAdvance();
    this.nextBtn.disabled = !ok;
    this.nextBtn.classList.toggle('cc-disabled', !ok);
  }

  // ---- step: Attributes --------------------------------------------

  buildAttributes() {
    const wrap = el('div', { class: 'cc-section cc-attributes' });
    wrap.appendChild(el('p', { class: 'cc-lead' },
      'Each attribute starts at ' + this.alloc.starting +
      '. Spend your Point Buy raising and lowering them.'));

    const summary = el('div', { class: 'cc-pointbuy' });
    wrap.appendChild(summary);

    const grid = el('div', { class: 'cc-attr-grid' });
    const refreshers = [];

    this.blob.attributes.forEach((attr) => {
      const valEl = el('span', { class: 'cc-attr-value' });
      const costEl = el('span', { class: 'cc-attr-cost' });
      const dec = el('button', {
        type: 'button', class: 'ce-btn ce-btn-tight cc-step-btn',
        'aria-label': 'Decrease ' + attr,
        onclick: () => { this.adjustAttr(attr, -1); refresh(); }
      }, '−');
      const inc = el('button', {
        type: 'button', class: 'ce-btn ce-btn-tight cc-step-btn',
        'aria-label': 'Increase ' + attr,
        onclick: () => { this.adjustAttr(attr, 1); refresh(); }
      }, '+');

      grid.appendChild(el('div', { class: 'cc-attr-row' },
        el('span', { class: 'cc-attr-name', text: attr.toUpperCase() }),
        dec, valEl, inc, costEl));

      refreshers.push(() => {
        valEl.textContent = String(this.state.attrs[attr]);
        const next = this.nextCost(attr);
        costEl.textContent = next == null ? 'max' : 'next: ' + next;
        dec.disabled = this.state.attrs[attr] <= this.alloc.min;
        inc.disabled = !this.canIncrease(attr);
      });
    });
    wrap.appendChild(grid);

    const refresh = () => {
      const rem = this.remaining();
      summary.innerHTML = '';
      summary.appendChild(el('span', { class: 'cc-pointbuy-label', text: 'Point Buy' }));
      summary.appendChild(el('span', {
        class: 'cc-pointbuy-value' + (rem < 0 ? ' cc-over' : ''),
        text: rem + ' / ' + this.alloc.pool
      }));
      refreshers.forEach((fn) => fn());
      this.refreshNav();
    };
    refresh();
    return wrap;
  }

  nextCost(attr) {
    const v = this.state.attrs[attr];
    if (v >= this.alloc.max) return null;
    return this.costOf(v + 1) - this.costOf(v);
  }

  canIncrease(attr) {
    const v = this.state.attrs[attr];
    if (v >= this.alloc.max) return false;
    const delta = this.costOf(v + 1) - this.costOf(v);
    return delta <= this.remaining();
  }

  adjustAttr(attr, dir) {
    const v = this.state.attrs[attr];
    if (dir > 0 && this.canIncrease(attr)) this.state.attrs[attr] = v + 1;
    else if (dir < 0 && v > this.alloc.min) this.state.attrs[attr] = v - 1;
  }

  // ---- step: Race ---------------------------------------------------

  buildRace() {
    const wrap = el('div', { class: 'cc-section cc-race' });

    const list = el('div', { class: 'cc-cards' });
    this.blob.races.forEach((race) => {
      const card = el('button', {
        type: 'button',
        class: 'cc-card' + (this.state.raceKey === race.key ? ' cc-selected' : ''),
        onclick: () => {
          this.state.raceKey = race.key;
          list.querySelectorAll('.cc-card').forEach((c) => c.classList.remove('cc-selected'));
          card.classList.add('cc-selected');
          this.refreshAttrBar();
          this.refreshNav();
        }
      });
      card.appendChild(el('div', { class: 'cc-card-title', text: race.label }));
      const props = el('div', { class: 'cc-card-props' });
      if (race.chain && race.chain !== race.label) props.appendChild(el('div', { class: 'cc-prop', text: race.chain }));
      if (race.size) props.appendChild(el('div', { class: 'cc-prop', text: 'Size: ' + race.size }));
      if (race.speed) props.appendChild(el('div', { class: 'cc-prop', text: 'Speed: ' + race.speed + ' ft' }));
      const adjs = this.blob.attributes
        .filter((a) => race.adjustments[a])
        .map((a) => a.toUpperCase() + ' ' + (race.adjustments[a] > 0 ? '+' : '') + race.adjustments[a]);
      props.appendChild(el('div', { class: 'cc-prop', text: 'Stats: ' + (adjs.length ? adjs.join(', ') : 'none') }));
      if (race.abilities.length) props.appendChild(el('div', { class: 'cc-prop', text: 'Abilities: ' + race.abilities.join(', ') }));
      card.appendChild(props);
      list.appendChild(card);
    });
    wrap.appendChild(list);
    return wrap;
  }

  // ---- step: Class --------------------------------------------------

  buildClass() {
    const wrap = el('div', { class: 'cc-section cc-class' });
    const list = el('div', { class: 'cc-cards' });

    this.blob.classes.forEach((cls) => {
      const card = el('button', {
        type: 'button',
        class: 'cc-card' + (this.state.classKey === cls.key ? ' cc-selected' : ''),
        onclick: () => {
          if (this.state.classKey !== cls.key) {
            this.state.classKey = cls.key;
            // A class change invalidates skill / spell picks.
            this.state.skills = {};
            this.state.setSuffix = {};
            this.state.spells = {};
            this.state.deity = null;
            this.state.domains = [];
          }
          list.querySelectorAll('.cc-card').forEach((c) => c.classList.remove('cc-selected'));
          card.classList.add('cc-selected');
          this.refreshNav();
        }
      });
      card.appendChild(el('div', { class: 'cc-card-title', text: cls.label }));
      const props = el('div', { class: 'cc-card-props' });
      props.appendChild(el('div', { class: 'cc-prop', text: 'Bonus skills: ' + cls.bonus_skills }));
      props.appendChild(el('div', { class: 'cc-prop', text: 'Mana / level: ' + cls.mana_per_level }));
      if (cls.martial) props.appendChild(el('div', { class: 'cc-prop', text: 'Martial: ' + cls.martial }));
      if (cls.saves.aligned.length) {
        props.appendChild(el('div', { class: 'cc-prop', text: 'Strong saves: ' + cls.saves.aligned.map((s) => s.toUpperCase()).join(', ') }));
      }
      if (cls.abilities.length) props.appendChild(el('div', { class: 'cc-prop', text: 'Level 1: ' + cls.abilities.join(', ') }));
      const sel = cls.spell_selection;
      if (sel) {
        let label;
        if (sel.mode === 'domain') label = 'Spells: deity & domains';
        else if (sel.mode === 'points') label = 'Spells: ' + sel.budget + ' points';
        else label = 'Spells: ' + sel.budget + ' known';
        props.appendChild(el('div', { class: 'cc-prop cc-prop-spell', text: label }));
      }
      card.appendChild(props);
      list.appendChild(card);
    });
    wrap.appendChild(list);
    return wrap;
  }

  // ---- step: Skills -------------------------------------------------

  buildSkills() {
    const wrap = el('div', { class: 'cc-section cc-skills' });
    const cls = this.currentClass();

    const counter = el('div', { class: 'cc-counter' });
    wrap.appendChild(counter);

    const groups = [
      ['aligned', 'Aligned'],
      ['unaligned', 'Unaligned'],
      ['opposed', 'Opposed']
    ];
    const boxes = [];

    groups.forEach(([key, label]) => {
      const keys = cls.skill_groups[key] || [];
      if (!keys.length) return;
      const group = el('div', { class: 'cc-skill-group cc-skill-' + key });
      group.appendChild(el('h3', { class: 'cc-skill-group-title', text: label }));
      const grid = el('div', { class: 'cc-skill-list' });

      keys.slice().sort((a, b) => this.skillLabel(a).localeCompare(this.skillLabel(b))).forEach((skillKey) => {
        const meta = this.blob.skill_catalog[skillKey] || {};
        const isSet = skillKey.endsWith('_');
        const box = el('input', {
          type: 'checkbox', class: 'cc-skill-box',
          checked: !!this.state.skills[skillKey]
        });
        const suffixInput = isSet ? el('input', {
          type: 'text', class: 'cc-skill-suffix', placeholder: 'specify…',
          value: this.state.setSuffix[skillKey] || ''
        }) : null;

        box.addEventListener('change', () => {
          this.state.skills[skillKey] = box.checked;
          this.updateSkillsUI(boxes, counter);
        });
        if (suffixInput) {
          suffixInput.addEventListener('input', () => {
            this.state.setSuffix[skillKey] = suffixInput.value;
            this.refreshNav();
          });
        }

        const row = el('label', { class: 'cc-skill-row', title: meta.description || '' },
          box,
          el('span', { class: 'cc-skill-name', text: this.skillLabel(skillKey) }),
          el('span', { class: 'cc-skill-attr', text: (meta.attribute || '').toUpperCase() }),
          suffixInput);
        boxes.push(box);
        grid.appendChild(row);
      });
      group.appendChild(grid);
      wrap.appendChild(group);
    });

    this.updateSkillsUI(boxes, counter);
    return wrap;
  }

  skillLabel(key) {
    const meta = this.blob.skill_catalog[key];
    return meta ? meta.label : key;
  }

  updateSkillsUI(boxes, counter) {
    const picked = this.checkedSkills().length;
    const max = this.pickCount();
    counter.innerHTML = '';
    counter.appendChild(el('span', { class: 'cc-counter-label', text: 'Skills' }));
    counter.appendChild(el('span', {
      class: 'cc-counter-value' + (picked > max ? ' cc-over' : ''),
      text: picked + ' / ' + max
    }));
    const full = picked >= max;
    boxes.forEach((b) => { b.disabled = full && !b.checked; });
    this.refreshNav();
  }

  // ---- step: Spells -------------------------------------------------

  buildSpells() {
    const sel = this.currentClass().spell_selection;
    if (sel.mode === 'domain') return this.buildDomain(sel);
    return this.buildSpellPicker(sel);
  }

  buildDomain(sel) {
    const wrap = el('div', { class: 'cc-section cc-domain' });
    const required = () => this.requiredDomainCount(sel);
    wrap.appendChild(el('p', { class: 'cc-lead' },
      'Choose a deity, then pick their domains. Each chosen domain grants its spells.'));

    const deitySel = el('select', { class: 'cc-select' },
      el('option', { value: '', text: 'Select a deity…' }),
      ...sel.deities.map((d) => el('option', { value: d.name, text: d.name, selected: this.state.deity === d.name })));

    const counter = el('div', { class: 'cc-counter' });
    const domainList = el('div', { class: 'cc-skill-list' });
    const spellList = el('div', { class: 'cc-domain-spells' });

    const deityDomains = () => {
      const deity = sel.deities.find((d) => d.name === this.state.deity);
      return deity ? deity.domains : [];
    };

    const refresh = () => {
      const need = required();
      counter.innerHTML = '';
      counter.appendChild(el('span', { class: 'cc-counter-label', text: 'Domains' }));
      counter.appendChild(el('span', {
        class: 'cc-counter-value' + (this.state.domains.length > need ? ' cc-over' : ''),
        text: this.state.domains.length + ' / ' + need
      }));

      const full = this.state.domains.length >= need;
      domainList.innerHTML = '';
      deityDomains().forEach((dom) => {
        const checked = this.state.domains.includes(dom.name);
        const box = el('input', { type: 'checkbox', class: 'cc-skill-box', checked: checked });
        box.disabled = full && !checked;
        box.addEventListener('change', () => {
          if (box.checked) this.state.domains.push(dom.name);
          else this.state.domains = this.state.domains.filter((n) => n !== dom.name);
          refresh();
        });
        domainList.appendChild(el('label', { class: 'cc-skill-row' },
          box,
          el('span', { class: 'cc-skill-name', text: dom.name }),
          dom.spells.length ? el('span', { class: 'cc-skill-attr', text: dom.spells.length + ' spell' + (dom.spells.length === 1 ? '' : 's') }) : null));
      });

      spellList.innerHTML = '';
      const chosen = deityDomains().filter((d) => this.state.domains.includes(d.name));
      const spells = chosen.flatMap((d) => d.spells);
      if (spells.length) {
        spellList.appendChild(el('div', { class: 'cc-domain-spells-title', text: 'Granted domain spells' }));
        spells.forEach((s) => spellList.appendChild(el('span', { class: 'cc-chip', text: s })));
      }
      this.refreshNav();
    };

    deitySel.addEventListener('change', () => {
      this.state.deity = deitySel.value || null;
      this.state.domains = [];
      refresh();
    });

    wrap.appendChild(el('div', { class: 'cc-field' }, el('label', { class: 'cc-field-label', text: 'Deity' }), deitySel));
    wrap.appendChild(counter);
    wrap.appendChild(domainList);
    wrap.appendChild(spellList);
    refresh();
    return wrap;
  }

  buildSpellPicker(sel) {
    const wrap = el('div', { class: 'cc-section cc-spells' });
    const counter = el('div', { class: 'cc-counter' });
    wrap.appendChild(counter);

    const byTier = {};
    (sel.spells || []).forEach((sp) => { (byTier[sp.tier] = byTier[sp.tier] || []).push(sp); });

    const boxes = [];
    Object.keys(byTier).map(Number).sort((a, b) => a - b).forEach((tier) => {
      const group = el('div', { class: 'cc-spell-group' });
      group.appendChild(el('h3', { class: 'cc-spell-tier', text: 'Tier ' + tier }));
      const grid = el('div', { class: 'cc-spell-list' });
      byTier[tier].forEach((sp) => {
        const box = el('input', { type: 'checkbox', class: 'cc-spell-box', checked: !!this.state.spells[sp.key] });
        box._spell = sp;
        box.addEventListener('change', () => {
          this.state.spells[sp.key] = box.checked;
          this.updateSpellsUI(sel, boxes, counter);
        });
        const row = el('label', { class: 'cc-spell-row' },
          box,
          el('span', { class: 'cc-spell-name', text: sp.label }),
          sel.mode === 'points' ? el('span', { class: 'cc-spell-cost', text: fmtNum(sp.cost) + ' pt' }) : null);
        boxes.push(box);
        grid.appendChild(row);
      });
      group.appendChild(grid);
      wrap.appendChild(group);
    });

    this.updateSpellsUI(sel, boxes, counter);
    return wrap;
  }

  updateSpellsUI(sel, boxes, counter) {
    counter.innerHTML = '';
    counter.appendChild(el('span', { class: 'cc-counter-label', text: sel.mode === 'points' ? 'Points spent' : 'Spells known' }));
    if (sel.mode === 'points') {
      const spent = this.spellSpent();
      const remaining = sel.budget - spent;
      counter.appendChild(el('span', { class: 'cc-counter-value' + (spent > sel.budget ? ' cc-over' : ''), text: fmtNum(spent) + ' / ' + sel.budget }));
      boxes.forEach((b) => { b.disabled = !b.checked && b._spell.cost > remaining; });
    } else {
      const picked = this.checkedSpells().length;
      counter.appendChild(el('span', { class: 'cc-counter-value' + (picked > sel.budget ? ' cc-over' : ''), text: picked + ' / ' + sel.budget }));
      const full = picked >= sel.budget;
      boxes.forEach((b) => { b.disabled = full && !b.checked; });
    }
    this.refreshNav();
  }

  // ---- step: Confirm ------------------------------------------------

  buildConfirm() {
    const wrap = el('div', { class: 'cc-section cc-confirm' });

    const nameInput = el('input', { type: 'text', class: 'cc-text', value: this.state.name, placeholder: 'Character name' });
    nameInput.addEventListener('input', () => { this.state.name = nameInput.value; this.refreshNav(); });
    const playerInput = el('input', { type: 'text', class: 'cc-text', value: this.state.player, placeholder: 'Player name (optional)' });
    playerInput.addEventListener('input', () => { this.state.player = playerInput.value; });

    wrap.appendChild(el('div', { class: 'cc-field' }, el('label', { class: 'cc-field-label', text: 'Character name' }), nameInput));
    wrap.appendChild(el('div', { class: 'cc-field' }, el('label', { class: 'cc-field-label', text: 'Player name' }), playerInput));

    const summary = el('dl', { class: 'cc-summary' });
    const race = this.currentRace();
    const cls = this.currentClass();
    const addRow = (label, value) => {
      summary.appendChild(el('dt', { class: 'cc-summary-key', text: label }));
      summary.appendChild(el('dd', { class: 'cc-summary-val', text: value }));
    };
    addRow('Race', race ? race.label : '—');
    addRow('Class', cls ? cls.label : '—');
    addRow('Attributes', this.blob.attributes.map((a) => a.toUpperCase() + ' ' + this.shownAttr(a)).join('  '));
    addRow('Skills', this.collectSkills().map((k) => this.summaryLabel(k)).join(', ') || 'none');
    const sel = cls && cls.spell_selection;
    if (sel && sel.mode === 'domain') {
      addRow('Deity', this.state.deity || '—');
      addRow('Domains', this.state.domains.join(', ') || '—');
    } else if (sel) {
      addRow('Spells', this.checkedSpells().join(', ') || 'none');
    }
    wrap.appendChild(summary);
    return wrap;
  }

  summaryLabel(concreteKey) {
    // Reverse a set-skill instance (craft_smithing) into "Craft: Smithing".
    const meta = this.blob.skill_catalog[concreteKey];
    if (meta) return meta.label;
    const m = Object.keys(this.blob.skill_catalog).find((k) => k.endsWith('_') && concreteKey.startsWith(k));
    if (m) {
      const suffix = concreteKey.slice(m.length).replace(/_/g, ' ');
      return this.blob.skill_catalog[m].label + ': ' + suffix.replace(/\b\w/g, (c) => c.toUpperCase());
    }
    return concreteKey;
  }

  // ---- create -------------------------------------------------------

  create() {
    const payload = {
      name: this.state.name.trim(),
      player: this.state.player.trim(),
      race: this.state.raceKey,
      class: this.state.classKey,
      attributes: this.state.attrs,
      skills: this.collectSkills(),
      spells: this.checkedSpells(),
      deity: this.state.deity,
      domains: this.state.domains
    };
    this.nextBtn.disabled = true;
    fetch(this.blob.create_url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
      .then((r) => r.json().catch(() => ({ ok: false, error: 'Unexpected server response' })))
      .then((data) => {
        if (data.ok && data.redirect) window.location = data.redirect;
        else { this.showError(data.error || 'Could not create character.'); this.refreshNav(); }
      })
      .catch(() => { this.showError('Network error while creating character.'); this.refreshNav(); });
  }

  showError(msg) {
    this.errorEl.textContent = msg;
    this.errorEl.hidden = false;
  }

  clearError() {
    this.errorEl.textContent = '';
    this.errorEl.hidden = true;
  }
}

function init() {
  const root = document.getElementById('character-creation');
  if (!root) return;
  const dataEl = document.getElementById('cc-data');
  if (!dataEl) return;
  let blob;
  try {
    blob = JSON.parse(dataEl.textContent);
  } catch (e) {
    return;
  }
  // eslint-disable-next-line no-new
  new CharacterCreator(root, blob);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
