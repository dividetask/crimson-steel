import { StepMachine } from './stepMachine.js';
import { SavePreview } from './savePreview.js';

// Collapse / expand of a Rolls wrapper, plus the "Confirm All" action
// inside a Save Resolution builder.
export class RollsWrapper {
  static collapse(wrapper) {
    const table = wrapper.querySelector(':scope > .roll-table') || wrapper.querySelector('.roll-table');
    if (!table) return;
    const groups = table.querySelectorAll('tbody.roll-group');
    groups.forEach((group, idx) => {
      const inputs = group.querySelectorAll('.result-input');
      const dois = inputs[0] ? inputs[0].value : '0';
      const crits = inputs[1] ? inputs[1].value : '0';
      const row = wrapper.querySelector('.rolls-result-row[data-roll-idx="' + idx + '"]');
      if (row) {
        const v = row.querySelector('.rolls-result-value');
        if (v) v.textContent = 'Successes ' + dois + ', Crits ' + crits;
      }
    });
    wrapper.dataset.state = 'collapsed';
    table.hidden = true;
    const actions = wrapper.querySelector('.rolls-actions');
    if (actions) actions.hidden = true;
    const results = wrapper.querySelector('.rolls-results');
    if (results) results.hidden = false;
  }

  static expand(wrapper) {
    wrapper.dataset.state = 'active';
    const table = wrapper.querySelector('.roll-table');
    if (table) table.hidden = false;
    const actions = wrapper.querySelector('.rolls-actions');
    if (actions) actions.hidden = false;
    const results = wrapper.querySelector('.rolls-results');
    if (results) results.hidden = true;
  }

  static confirmAllInSave(save) {
    const diceCtrl = save.querySelector('.step-controls[data-step="dice"]');
    if (!diceCtrl || diceCtrl.dataset.state !== 'active') return;
    const inputs = save.querySelectorAll('.step-body-dice .result-input');
    const dois = inputs.length > 0 ? inputs[0].value : '0';
    const crits = inputs.length > 1 ? inputs[1].value : '0';
    const spDois = save.querySelector('.sp-dois');
    if (spDois) spDois.value = dois;
    StepMachine.completeStep(save, 'dice', 'Successes: ' + dois + '   Crits: ' + crits);
    SavePreview.recompute(save);
  }
}
