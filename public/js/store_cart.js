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
  // merges identical ones: a Guidance Bonus, or a magical weapon's
  // properties + tier.
  function variantKey(bonus, extra) {
    if (extra && extra.properties) return 'p' + JSON.stringify(extra.properties) + 't' + (extra.tier || '');
    if (bonus) return 'b' + bonus;
    return '';
  }

  // Add (or merge) one line. Quantities <= 0 are ignored. Lines merge only
  // when item, variant, and recipient all match. `extra` (optional) carries
  // a magical weapon's { properties, tier, label }.
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
                      label: (extra && extra.label) || null });
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

  // The selected Guidance Bonus on a magical-item card: { bonus, price }
  // from the `+N` dropdown's current option. null for ordinary gear.
  function selectedBonus(card) {
    const select = card.querySelector('.provision-bonus-select');
    if (!select) return null;
    const opt = select.options[select.selectedIndex];
    return { bonus: parseInt(select.value, 10),
             price: opt ? parseFloat(opt.dataset.price) || 0 : 0 };
  }

  function fromCard(card) {
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
                        tier: st.tier, label: st.label };
        addLine(st.weapon.name, null, st.price, r.id, r.name, r.isPc, 1, extra);
      }
      render();
      return;
    }

    if (card.classList.contains('provision-card-batch')) {
      // Alchemy / Magical: the "selected" box (dropdown recipient, maybe
      // an enemy) plus one box per Player Character.
      const sel = selectedRecipient(card);
      const selBox = card.querySelector('.provision-qty-selected');
      if (sel) addLine(item, bonus, price, sel.id, sel.name, sel.isPc, selBox && selBox.value);
      card.querySelectorAll('.provision-qty-pc').forEach((box) => {
        addLine(item, bonus, price, box.dataset.recipientId, box.dataset.recipientName, true, box.value);
      });
      if (selBox) selBox.value = 0;
      card.querySelectorAll('.provision-qty-pc').forEach((box) => { box.value = 0; });
    } else {
      // Weapons / Armor: the dropdown recipient + single quantity box.
      const r = selectedRecipient(card);
      const box = card.querySelector('.provision-qty-single');
      if (r) addLine(item, bonus, price, r.id, r.name, r.isPc, box && box.value);
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
    const total = lines.reduce((s, l) => s + (l.isPc ? l.unitPrice * l.quantity : 0), 0);
    countEl.textContent = count;
    totalEl.textContent = fmt(total);

    linesEl.textContent = '';
    lines.forEach((l, idx) => {
      const li = document.createElement('li');
      li.className = 'provision-cart-line';

      const desc = document.createElement('span');
      desc.className = 'provision-cart-line-desc';
      const cost = l.isPc ? `${fmt(l.unitPrice * l.quantity)} gp` : 'free';
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
