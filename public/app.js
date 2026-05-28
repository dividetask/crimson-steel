// Entry point for the Status-page stubs. Wires document-level event
// delegation to the UI controllers. All dice math lives in the Dice /
// Check Resolution modules under /js; the controllers under /js/ui drive
// the DOM.
import { RollController } from './js/ui/rollController.js';
import { RollsWrapper } from './js/ui/rollsWrapper.js';
import { StepMachine } from './js/ui/stepMachine.js';
import { SavePreview } from './js/ui/savePreview.js';
// Standalone page interactions (image lightbox, text modal, creature
// roster groups, encounter rolls). Imported for its side effects.
import './js/ui/pageInteractions.js';

document.addEventListener('click', function (e) {
  const badge = e.target.closest('.mod-badge');
  if (badge) {
    badge.classList.add('show-tip');
    if (badge._tipTimer) clearTimeout(badge._tipTimer);
    badge._tipTimer = setTimeout(function () {
      badge.classList.remove('show-tip');
    }, 3000);
    return;
  }

  const rollBtn = e.target.closest('.btn-roll-all');
  if (rollBtn) {
    const wrapper = rollBtn.closest('.rolls-wrapper');
    if (wrapper) RollController.rollAll(wrapper);
    return;
  }

  if (e.target.closest('.btn-confirm-all')) {
    const save = e.target.closest('.save-resolution');
    if (save) RollsWrapper.confirmAllInSave(save);
    return;
  }

  const confirmBtn = e.target.closest('.btn-confirm');
  if (confirmBtn) {
    const wrap = confirmBtn.closest('.rolls-wrapper');
    if (wrap) RollsWrapper.collapse(wrap);
    return;
  }

  const changeBtn = e.target.closest('.btn-rolls-change');
  if (changeBtn) {
    const wrap2 = changeBtn.closest('.rolls-wrapper');
    if (wrap2) RollsWrapper.expand(wrap2);
    return;
  }

  const lockBtn = e.target.closest('.lock-btn');
  if (lockBtn) {
    lockBtn.classList.toggle('locked');
    return;
  }

  const modBtn = e.target.closest('.cr-mod-btn');
  if (modBtn) {
    StepMachine.handleModClick(modBtn);
    return;
  }

  const stepNone = e.target.closest('.cr-step-none');
  if (stepNone) {
    StepMachine.handleStepNone(stepNone);
    return;
  }

  const stepChange = e.target.closest('.cr-step-change');
  if (stepChange) {
    StepMachine.handleStepChange(stepChange);
    return;
  }

  const saveConfirm = e.target.closest('.btn-save-confirm');
  if (saveConfirm) {
    SavePreview.handleConfirm(saveConfirm);
    return;
  }
});

document.addEventListener('change', function (e) {
  SavePreview.syncFromResultInput(e.target);
});
