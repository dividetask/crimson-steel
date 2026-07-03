// Store Shopping Cart — client-side provisioning basket.
//
// "Add" buttons push lines into an in-memory cart; the cart panel on the
// right is shown only when non-empty and can be collapsed/expanded.
// Nothing hits the server until Purchase, which POSTs every line to
// /store/checkout as JSON. The server recomputes prices and PC-status,
// so the cart's totals are display-only.
//
// A cart line is { item, bonus, recipientId, recipientName, isPc,
// unitPrice, quantity, properties, tier, label, variantKey }. Lines with
// the same item + variant + recipient merge by summing quantity. `bonus`
// is the Guidance Bonus (+N) for a Guidance item; `properties` + `tier`
// describe a magical weapon (Elemental, Vicious, Glory, …); both null for
// ordinary gear. `variantKey` distinguishes those variants when merging.

const root = document.querySelector('.provision');
if (root) initCart(root);

function initCart(root) {
  const checkoutUrl = root.dataset.checkoutUrl || '/store/checkout';
  const cartEl   = root.querySelector('[data-cart]');
  const linesEl  = root.querySelector('[data-cart-lines]');
  const countEl  = root.querySelector('[data-cart-count]');
  const totalEl  = root.querySelector('[data-cart-total]');
  const bodyEl   = root.querySelector('[data-cart-body]');
  const flashEl  = root.querySelector('[data-store-flash]');

  let lines = [];

  const fmt = (n) => {
    const r = Math.round(n * 100) / 100;
    return Number.isInteger(r) ? String(r) : r.toFixed(2);
  };

  function selectedRecipient(card) {
    const section = card.closest('.provision-section');
    const select  = section && section.querySelector('.provision-creature-select');
    if (!select) return null;
    const opt = select.options[select.selectedIndex];
    return { id: select.value, name: opt ? opt.textContent.trim() : select.value,
             isPc: opt ? opt.dataset.pc === 'true' : false };
  }

  // A string that distinguishes variants of the same item so the cart only
  // merges identical ones: a Guidance Bonus, a magical weapon's properties +
  // tier, a magical armor's tier, or a Scroll/Potion's form + tier. A gift
  // (free DM give) never merges with a paid line, so it carries a `G` prefix.
  function variantKey(bonus, extra) {
    const g = extra && extra.gift ? 'G' : '';
    if (extra && extra.spellForm) return g + 's' + (extra.form || '') + 't' + (extra.tier || '');
    if (extra && extra.properties) return g + 'p' + JSON.stringify(extra.properties) + 't' + (extra.tier || '');
    if (extra && extra.tier) return g + 'a' + 't' + extra.tier;
    if (bonus) return g + 'b' + bonus;
    return g;
  }

  // Add (or merge) one line. Quantities <= 0 are ignored. Lines merge only
  // when item, variant, and recipient all match. `extra` (optional) carries
  // a magical weapon's { properties, tier, label }, a spell form's
  // { spellForm, form, tier, label }, and/or a { gift } flag (free give).
  function addLine(item, bonus, unitPrice, recipientId, recipientName, isPc, quantity, extra) {
    const qty = parseInt(quantity, 10);
    if (!recipientId || !Number.isFinite(qty) || qty <= 0) return;
    const vk = variantKey(bonus, extra);
    const existing = lines.find(
      (l) => l.item === item && l.variantKey === vk && l.recipientId === recipientId);
    if (existing) existing.quantity += qty;
    else lines.push({ item, bonus, unitPrice, recipientId, recipientName, isPc, quantity: qty,
                      variantKey: vk,
                      properties: (extra && extra.properties) || null,
                      tier: (extra && extra.tier) || null,
                      label: (extra && extra.label) || null,
                      gift: !!(extra && extra.gift) });
  }

  // The Scrolls/Potions/Oils data embedded on a card:
  // [{ name, scroll, potion, oil, tiers:[{tier, scroll, potion, oil}] }].
  function spellItemData(card) {
    return JSON.parse(card.dataset.spells || '[]');
  }

  // A Spell offers the Scroll form always; Potion / Oil only when its data flag
  // is set.
  function spellSupportsForm(sp, form) {
    return form === 'scroll' ? true : !!sp[form];
  }

  // Fill the Spell dropdown with just the Spells that offer the selected Form,
  // so the Form choice drives the Spell list (and no option ever disables).
  function populateSpellOptions(card) {
    const spells = spellItemData(card);
    const form = card.querySelector('.spellitem-form').value;
    const sel = card.querySelector('.spellitem-spell');
    const prev = sel.value;
    sel.innerHTML = '';
    spells.filter((s) => spellSupportsForm(s, form)).forEach((s) => {
      const o = document.createElement('option');
      o.value = s.name; o.textContent = s.name;
      sel.appendChild(o);
    });
    if (Array.from(sel.options).some((o) => o.value === prev)) sel.value = prev;
  }

  // Fill the Tier dropdown from the selected Spell's tiers.
  function populateSpellTiers(card) {
    const spells = spellItemData(card);
    const name = card.querySelector('.spellitem-spell').value;
    const tierSel = card.querySelector('.spellitem-tier');
    const sp = spells.find((s) => s.name === name) || { tiers: [] };
    const prev = tierSel.value;
    tierSel.innerHTML = '';
    sp.tiers.forEach((t) => {
      const o = document.createElement('option');
      o.value = t.tier; o.textContent = t.tier;
      tierSel.appendChild(o);
    });
    if (sp.tiers.some((t) => String(t.tier) === prev)) tierSel.value = prev;
  }

  // Read a Scrolls/Potions/Oils card into a priced state. The Spell list is
  // already filtered to the Form, so the only invalid case is an empty list.
  function spellItemState(card) {
    const spells = spellItemData(card);
    const form = card.querySelector('.spellitem-form').value;
    const name = card.querySelector('.spellitem-spell').value;
    const tier = parseInt(card.querySelector('.spellitem-tier').value, 10) || 0;
    const sp = spells.find((s) => s.name === name);
    const row = sp && (sp.tiers.find((t) => t.tier === tier) || sp.tiers[0]);
    const price = row ? (row[form] || 0) : 0;
    const item = `${form.charAt(0).toUpperCase()}${form.slice(1)} of ${name}`;
    const label = `${item} (Tier ${tier})`;
    return { form, name, tier, price, item, label, valid: !!sp };
  }

  // Refresh a Scrolls/Potions/Oils card's shown price and buttons.
  function updateSpellItem(card) {
    const st = spellItemState(card);
    const amount = card.querySelector('.provision-price-amount');
    if (amount) amount.textContent = fmt(st.price);
    card.querySelectorAll('.provision-add, .provision-give').forEach((b) => { b.disabled = !st.valid; });
  }

  // Read a Magical Weapon card's three selects into a priced, validated
  // state: { weapon, property, tier, price, valid, note, label }. Price =
  // base weapon + Tier Surcharge + Property cost (the server reprices at
  // checkout). Invalid when the Tier is below the Property's minimum or the
  // Property can't go on the weapon's melee/ranged category.
  function magicWeaponState(card) {
    const wsel = card.querySelector('.mw-weapon');
    const psel = card.querySelector('.mw-property');
    const tsel = card.querySelector('.mw-tier');
    const wopt = wsel.options[wsel.selectedIndex];
    const popt = psel.options[psel.selectedIndex];
    const topt = tsel.options[tsel.selectedIndex];
    const weapon = { name: wsel.value, category: wopt.dataset.category, base: parseFloat(wopt.dataset.base) || 0 };
    const property = { name: popt.dataset.name, subtype: popt.dataset.subtype || null,
                       label: popt.textContent.trim(),
                       cost: parseFloat(popt.dataset.cost) || 0,
                       minTier: parseInt(popt.dataset.minTier, 10) || 1,
                       applies: (popt.dataset.applies || '').split(',') };
    const tier = parseInt(tsel.value, 10) || 0;
    const surcharge = parseFloat(topt.dataset.surcharge) || 0;
    let valid = true; let note = '';
    if (tier < property.minTier) { valid = false; note = `${property.name} needs tier ${property.minTier}+.`; }
    else if (!property.applies.includes(weapon.category)) { valid = false; note = `${property.name} can't go on a ${weapon.category} weapon.`; }
    const price = weapon.base + surcharge + property.cost;
    const label = `+${tier} ${weapon.name} (${property.label})`;
    return { weapon, property, tier, price, valid, note, label };
  }

  // Refresh a Magical Weapon card's shown price, validity note, and Add
  // button as its selects change.
  function updateMagicWeapon(card) {
    const st = magicWeaponState(card);
    const amount = card.querySelector('.provision-price-amount');
    if (amount) amount.textContent = fmt(st.price);
    const note = card.querySelector('.mw-note');
    if (note) { note.textContent = st.valid ? '' : st.note; note.hidden = st.valid; }
    const btn = card.querySelector('.provision-add');
    if (btn) btn.disabled = !st.valid;
  }

  // Read a Magical Armor card's two selects into a priced state:
  // { armor, tier, price, label }. Price = base armor + Tier Surcharge (the
  // server reprices at checkout). No Properties — the only enchantment is the
  // Tier — so there is nothing to invalidate.
  function magicArmorState(card) {
    const asel = card.querySelector('.ma-armor');
    const tsel = card.querySelector('.ma-tier');
    const aopt = asel.options[asel.selectedIndex];
    const topt = tsel.options[tsel.selectedIndex];
    const armor = { name: asel.value, base: parseFloat(aopt.dataset.base) || 0 };
    const tier = parseInt(tsel.value, 10) || 0;
    const surcharge = parseFloat(topt.dataset.surcharge) || 0;
    const price = armor.base + surcharge;
    const label = `+${tier} ${armor.name}`;
    return { armor, tier, price, label };
  }

  // Refresh a Magical Armor card's shown price as its selects change.
  function updateMagicArmor(card) {
    const st = magicArmorState(card);
    const amount = card.querySelector('.provision-price-amount');
    if (amount) amount.textContent = fmt(st.price);
  }

  // The selected Guidance Bonus on a magical-item card: { bonus, price }
  // from the `+N` dropdown's current option. null for ordinary gear.
  function selectedBonus(card) {
    const select = card.querySelector('.provision-bonus-select');
    if (!select) return null;
    const opt = select.options[select.selectedIndex];
    return { bonus: parseInt(select.value, 10),
             price: opt ? parseFloat(opt.dataset.price) || 0 : 0 };
  }

  function fromCard(card, opts) {
    const gift  = !!(opts && opts.gift);
    const item  = card.dataset.item;
    // A magical-item card prices off the chosen +N option; everything
    // else off the card's flat data-price.
    const gb    = selectedBonus(card);
    const price = gb ? gb.price : (parseFloat(card.dataset.price) || 0);
    const bonus = gb ? gb.bonus : null;

    if (card.classList.contains('provision-card-magicweapon')) {
      // Magical Weapons: weapon + property + tier from three selects, bought
      // (one) for the section's dropdown recipient. An invalid combination
      // adds nothing.
      const st = magicWeaponState(card);
      if (!st.valid) { updateMagicWeapon(card); return; }
      const r = selectedRecipient(card);
      if (r) {
        const extra = { properties: [{ name: st.property.name, subtype: st.property.subtype || null }],
                        tier: st.tier, label: st.label, gift };
        addLine(st.weapon.name, null, st.price, r.id, r.name, r.isPc, 1, extra);
      }
      render();
      return;
    }

    if (card.classList.contains('provision-card-magicarmor')) {
      // Magical Armor: armor + tier from two selects, bought (one) for the
      // section's dropdown recipient. No Properties to validate.
      const st = magicArmorState(card);
      const r = selectedRecipient(card);
      if (r) {
        const extra = { tier: st.tier, label: st.label, gift };
        addLine(st.armor.name, null, st.price, r.id, r.name, r.isPc, 1, extra);
      }
      render();
      return;
    }

    if (card.classList.contains('provision-card-spellitem')) {
      // Scrolls & Potions: spell + form + tier from three selects, bought
      // (one) for the section's dropdown recipient. A Potion of a Spell with
      // no potion form adds nothing.
      const st = spellItemState(card);
      if (!st.valid) { updateSpellItem(card); return; }
      const r = selectedRecipient(card);
      if (r) {
        const extra = { spellForm: true, form: st.form, tier: st.tier, label: st.label, gift };
        addLine(st.item, null, st.price, r.id, r.name, r.isPc, 1, extra);
      }
      render();
      return;
    }

    if (card.classList.contains('provision-card-batch')) {
      // Alchemy / Magical: the "selected" box (dropdown recipient, maybe
      // an enemy) plus one box per Player Character.
      const sel = selectedRecipient(card);
      const selBox = card.querySelector('.provision-qty-selected');
      if (sel) addLine(item, bonus, price, sel.id, sel.name, sel.isPc, selBox && selBox.value, { gift });
      card.querySelectorAll('.provision-qty-pc').forEach((box) => {
        addLine(item, bonus, price, box.dataset.recipientId, box.dataset.recipientName, true, box.value, { gift });
      });
      if (selBox) selBox.value = 0;
      card.querySelectorAll('.provision-qty-pc').forEach((box) => { box.value = 0; });
    } else {
      // Weapons / Armor: the dropdown recipient + single quantity box.
      const r = selectedRecipient(card);
      const box = card.querySelector('.provision-qty-single');
      if (r) addLine(item, bonus, price, r.id, r.name, r.isPc, box && box.value, { gift });
      if (box) box.value = 1;
    }
    render();
  }

  function removeLine(idx) {
    lines.splice(idx, 1);
    render();
  }

  function render() {
    const count = lines.reduce((n, l) => n + l.quantity, 0);
    // A gift is free even for a PC, so it never contributes to the total.
    const total = lines.reduce((s, l) => s + (l.isPc && !l.gift ? l.unitPrice * l.quantity : 0), 0);
    countEl.textContent = count;
    totalEl.textContent = fmt(total);

    linesEl.textContent = '';
    lines.forEach((l, idx) => {
      const li = document.createElement('li');
      li.className = 'provision-cart-line';

      const desc = document.createElement('span');
      desc.className = 'provision-cart-line-desc';
      const cost = l.gift ? 'gift' : (l.isPc ? `${fmt(l.unitPrice * l.quantity)} gp` : 'free');
      const label = l.label || (l.bonus ? `+${l.bonus} ${l.item}` : l.item);
      desc.textContent = `${l.quantity}× ${label} → ${l.recipientName} (${cost})`;

      const rm = document.createElement('button');
      rm.type = 'button';
      rm.className = 'provision-cart-remove';
      rm.setAttribute('aria-label', 'Remove');
      rm.textContent = '×';
      rm.addEventListener('click', () => removeLine(idx));

      li.append(desc, rm);
      linesEl.append(li);
    });

    cartEl.hidden = lines.length === 0;
  }

  function showFlash(type, message) {
    if (!flashEl) return;
    flashEl.textContent = message;
    flashEl.className = `store-flash store-flash-${type}`;
    flashEl.hidden = false;
    flashEl.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  async function purchase(btn) {
    if (lines.length === 0) return;
    btn.disabled = true;
    const payload = {
      lines: lines.map((l) => {
        const line = { item: l.item, recipient_id: l.recipientId, quantity: l.quantity };
        if (l.bonus) line.guidance_bonus = l.bonus;
        if (l.properties) { line.properties = l.properties; line.tier = l.tier; }
        else if (l.tier) { line.tier = l.tier; } // magical armor or scroll/potion: tier
        if (l.gift) line.gift = true;
        return line;
      }),
    };
    try {
      const res = await fetch(checkoutUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const data = await res.json().catch(() => ({}));
      showFlash(data.type || (res.ok ? 'success' : 'error'),
                data.message || (res.ok ? 'Purchase complete.' : 'Purchase failed.'));
      if (data.ok) { lines = []; render(); }
    } catch (e) {
      showFlash('error', 'Could not reach the server. Nothing was purchased.');
    } finally {
      btn.disabled = false;
    }
  }

  // ---- wiring ----
  root.querySelectorAll('.provision-add').forEach((btn) => {
    btn.addEventListener('click', () => fromCard(btn.closest('.provision-card')));
  });

  // "Give" (DM only): the same add, marked as a free gift.
  root.querySelectorAll('.provision-give').forEach((btn) => {
    btn.addEventListener('click', () => fromCard(btn.closest('.provision-card'), { gift: true }));
  });

  // Scrolls/Potions/Oils cards: Form drives the Spell list; Spell drives the
  // Tier list; any change reprices.
  root.querySelectorAll('.provision-card-spellitem').forEach((card) => {
    card.querySelector('.spellitem-form').addEventListener('change', () => {
      populateSpellOptions(card);
      populateSpellTiers(card);
      updateSpellItem(card);
    });
    card.querySelector('.spellitem-spell').addEventListener('change', () => {
      populateSpellTiers(card);
      updateSpellItem(card);
    });
    card.querySelector('.spellitem-tier').addEventListener('change', () => updateSpellItem(card));
    populateSpellOptions(card);
    populateSpellTiers(card);
    updateSpellItem(card);
  });

  // Magical-item cards: changing the +N Bonus updates the card's shown
  // price to the chosen option's price (client-side; the server reprices
  // at checkout regardless).
  root.querySelectorAll('.provision-bonus-select').forEach((select) => {
    select.addEventListener('change', () => {
      const card = select.closest('.provision-card');
      const gb = selectedBonus(card);
      const amount = card && card.querySelector('.provision-price-amount');
      if (gb && amount) amount.textContent = fmt(gb.price);
    });
  });

  // Magical Weapon cards: any of the three selects re-prices + re-validates.
  root.querySelectorAll('.provision-card-magicweapon').forEach((card) => {
    card.querySelectorAll('.mw-weapon, .mw-property, .mw-tier').forEach((sel) => {
      sel.addEventListener('change', () => updateMagicWeapon(card));
    });
    updateMagicWeapon(card);
  });

  // Magical Armor cards: either select (armor / tier) re-prices.
  root.querySelectorAll('.provision-card-magicarmor').forEach((card) => {
    card.querySelectorAll('.ma-armor, .ma-tier').forEach((sel) => {
      sel.addEventListener('change', () => updateMagicArmor(card));
    });
    updateMagicArmor(card);
  });

  const toggle = root.querySelector('[data-cart-toggle]');
  if (toggle) {
    toggle.addEventListener('click', () => {
      const collapsed = cartEl.classList.toggle('provision-cart-collapsed');
      toggle.setAttribute('aria-expanded', String(!collapsed));
      if (bodyEl) bodyEl.hidden = collapsed;
    });
  }

  const clearBtn = root.querySelector('[data-cart-clear]');
  if (clearBtn) clearBtn.addEventListener('click', () => { lines = []; render(); });

  const purchaseBtn = root.querySelector('[data-cart-purchase]');
  if (purchaseBtn) purchaseBtn.addEventListener('click', () => purchase(purchaseBtn));

  render();
}
