// The Save Resolution / Builder step machine. A save-resolution wrapper
// hosts a chain of step-controls; one step is active at a time. Selecting
// a modifier magnitude, "(none)", or "Change" advances/rewinds the chain
// and keeps each Roll's data-config and modifier badge rows in sync.
import { RollRows } from './rollRows.js';

export class StepMachine {
  static handleModClick(btn) {
    const save = btn.closest('.save-resolution');
    if (!save) return;
    const stepEl = btn.closest('.step-body') || btn.closest('.step-controls');
    if (!stepEl) return;
    const kind = stepEl.dataset.step;
    if (kind === 'reroll' || kind === 'mass_reroll' || kind === 'nudge') {
      StepMachine.applyRollModifier(btn);
    }
    const label = btn.dataset.label || '';
    const signLabel = btn.textContent.trim();
    StepMachine.completeStep(save, kind, signLabel + (label ? ' ' + label : ''));
  }

  static applyRollModifier(btn) {
    const rollIdx = parseInt(btn.dataset.rollIdx, 10);
    const kind = btn.dataset.kind;
    const sign = btn.dataset.sign;
    const count = btn.dataset.count ? parseInt(btn.dataset.count, 10) : null;
    const label = btn.dataset.label;

    const save = btn.closest('.save-resolution');
    if (!save) return;
    const groups = save.querySelectorAll('tbody.roll-group');
    const group = groups[rollIdx];
    if (!group) return;

    const cfg = JSON.parse(group.dataset.config);
    if (kind === 'mass_reroll') {
      cfg.mass_reroll = { sign: sign };
    } else {
      cfg[kind] = { sign: sign, count: count, max: false };
    }
    group.dataset.config = JSON.stringify(cfg);
    StepMachine.updateModBadge(group, kind, cfg[kind], label);
  }

  static clearRollModifier(save, kind) {
    save.querySelectorAll('tbody.roll-group').forEach((group) => {
      const cfg = JSON.parse(group.dataset.config);
      cfg[kind] = null;
      group.dataset.config = JSON.stringify(cfg);
      StepMachine.updateModBadge(group, kind, null, '');
    });
  }

  static updateModBadge(group, kind, mod, label) {
    const rowClass =
      kind === 'reroll' ? '.row-reroll' : kind === 'mass_reroll' ? '.row-mass-reroll' : '.row-nudge';
    const col = kind === 'nudge' ? 1 : 0;
    let badgeText = '';
    if (mod) {
      const signCh = mod.sign === 'neg' ? '-' : '+';
      badgeText = kind === 'mass_reroll' ? signCh + '*' : signCh + mod.count;
    }
    RollRows.setModRow(group, rowClass, col, badgeText, label);
  }

  static completeStep(save, kind, summaryText) {
    if (!save || !kind) return;

    const ctrl = save.querySelector('.step-controls[data-step="' + kind + '"]');
    if (ctrl) ctrl.dataset.state = 'complete';
    const body = save.querySelector('.step-body[data-step="' + kind + '"]');
    if (body) body.dataset.state = 'complete';

    const summary = save.querySelector('.step-summary[data-step="' + kind + '"]');
    if (summary) {
      const v = summary.querySelector('.step-summary-value');
      if (v) v.textContent = summaryText;
      summary.hidden = false;
    }
    StepMachine.activateNextStep(save);
  }

  static handleStepNone(btn) {
    const save = btn.closest('.save-resolution');
    if (!save) return;
    const kind = btn.dataset.step;
    if (kind === 'reroll' || kind === 'mass_reroll' || kind === 'nudge') {
      StepMachine.clearRollModifier(save, kind);
    }
    StepMachine.completeStep(save, kind, '(none)');
  }

  static handleStepChange(btn) {
    const save = btn.closest('.save-resolution');
    if (!save) return;
    const kind = btn.dataset.step;

    if (kind === 'reroll' || kind === 'mass_reroll' || kind === 'nudge') {
      StepMachine.clearRollModifier(save, kind);
    }

    const thisCtrl = save.querySelector('.step-controls[data-step="' + kind + '"]');
    const thisBody = save.querySelector('.step-body[data-step="' + kind + '"]');
    const thisSumm = save.querySelector('.step-summary[data-step="' + kind + '"]');
    if (thisSumm) thisSumm.hidden = true;
    if (thisCtrl) thisCtrl.dataset.state = 'active';
    if (thisBody) thisBody.dataset.state = 'active';

    const chain = save.querySelectorAll('.step-controls');
    let rewind = false;
    chain.forEach((el) => {
      if (rewind) {
        const sk = el.dataset.step;
        el.dataset.state = 'pending';
        const body = save.querySelector('.step-body[data-step="' + sk + '"]');
        if (body) body.dataset.state = 'pending';
        const summ = save.querySelector('.step-summary[data-step="' + sk + '"]');
        if (summ) summ.hidden = true;
        if (sk === 'reroll' || sk === 'mass_reroll' || sk === 'nudge') {
          StepMachine.clearRollModifier(save, sk);
        }
      }
      if (el === thisCtrl) rewind = true;
    });
  }

  static activateNextStep(save) {
    if (!save) return;
    const chain = save.querySelectorAll('.step-controls');
    for (let i = 0; i < chain.length; i++) {
      const el = chain[i];
      if (el.dataset.state === 'pending') {
        el.dataset.state = 'active';
        const kind = el.dataset.step;
        const body = save.querySelector('.step-body[data-step="' + kind + '"]');
        if (body) body.dataset.state = 'active';
        return;
      }
    }
  }
}
