// Recomputes the Conditions Save Resolution preview after Roll All
// populates the dice: Net Magnitude, effect amount, and the Potency
// delta. Reads the DoIS the DM accepted (or overrode) and the static
// preview_data the stub was rendered with.
export class SavePreview {
  static recompute(save) {
    const data = JSON.parse(save.dataset.preview);
    const disp = parseInt(save.querySelector('.sp-dois').value, 10) || 0;
    const successes = Math.max(0, disp);
    const failures = Math.max(0, -disp);

    const divisor = data.potency_divisor;
    const potencyBefore = data.potency_before;
    const magnitude = 1 + Math.floor(potencyBefore / divisor);
    const netMagnitude = Math.max(0, magnitude - successes);

    save.querySelector('.sp-net-mag').value = netMagnitude;

    const amtInput = save.querySelector('.sp-effect-amount');
    if (amtInput) {
      if (data.effect.kind === 'named_effect') {
        amtInput.value = netMagnitude > 0 ? data.effect.name : '(none)';
      } else {
        amtInput.value = netMagnitude;
      }
    }

    // Potency evolution: -floor(decay) - floor(successes*per_success)
    //                    + floor(failures*per_failure)
    const tier = data.creature_tier;
    function subTier(v) {
      if (v === 'tier' || v === '"tier"') return tier <= 0 ? 0.5 : tier;
      return Number(v);
    }
    // Affliction rule overrides aren't part of preview_data; this is a
    // rough preview using defaults (1, 1, "tier"). The DM can override
    // the New Potency input directly.
    const decay = subTier('tier');
    const perS = 1;
    const perF = 1;
    const delta = -Math.floor(decay) - Math.floor(successes * perS) + Math.floor(failures * perF);
    const newPot = Math.max(0, potencyBefore + delta);
    save.querySelector('.sp-new-potency').value = newPot;

    const btn = save.querySelector('.btn-save-confirm');
    if (btn) btn.disabled = false;
  }

  static handleConfirm(btn) {
    const save = btn.closest('.save-resolution');
    if (!save) return;
    btn.disabled = true;

    // Live stub (Start of Turn): POST the rolled DoIS to Conditions'
    // Resolve Affliction. Absent data-resolve-url (e.g. the Status demo):
    // no server mutation — just leave the button disabled.
    const url = save.getAttribute('data-resolve-url');
    if (!url) return;

    const dois = parseInt(save.querySelector('.sp-dois').value, 10) || 0;
    const body = new FormData();
    body.append('combatant_id', save.getAttribute('data-resolve-combatant'));
    body.append('affliction', save.getAttribute('data-resolve-affliction'));
    body.append('dois', String(dois));
    fetch(url, { method: 'POST', body })
      .then(function (r) { return r.json().catch(function () { return {}; }); })
      .then(function () {
        // Reload so the resolution shows: the Combat Tracker's HP / badges
        // update and the now-resolved (or rescheduled) Affliction drops off
        // the Start of Turn pane.
        window.location.reload();
      })
      .catch(function () { btn.disabled = false; });
  }

  // Wire a change on a Save's DoIS input to recompute the preview. Roll
  // All updates dice and dispatches the change; the DM may also type a
  // DoIS directly.
  static syncFromResultInput(target) {
    const resultInput = target.closest('.result-input');
    if (!resultInput) return;
    const save = target.closest('.save-resolution');
    if (!save) return;
    const first = save.querySelector('.result-input');
    if (first) save.querySelector('.sp-dois').value = first.value;
    SavePreview.recompute(save);
  }
}
