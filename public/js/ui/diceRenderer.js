// Renders dice (and Starting Successes/Failures) as the colored .die
// boxes the stubs use. Pure string production — no DOM mutation.
export class DiceRenderer {
  static dieClass(value, tn, dieSize) {
    if (value === null || value === undefined) return 'empty';
    if (value === 1) return 'fail';
    if (value === dieSize) return 'crit';
    if (value >= tn) return 'success';
    return 'neutral';
  }

  // Starting Successes / Failures render as small filled squares before
  // the rolled dice on the initial row. Modifier rows reserve the same
  // width via invisible spacers ('spacer' mode) so each die column stays
  // aligned with the initial row above it.
  static renderStartingSquares(startingValue, mode) {
    if (!startingValue) return '';
    const abs = Math.abs(startingValue);
    const cls = startingValue > 0 ? 'success' : 'fail';
    const spacer = mode === 'spacer' ? ' starting-spacer' : '';
    let out = '';
    for (let i = 0; i < abs; i++) {
      out += '<span class="die ' + cls + ' starting-die' + spacer + '">&nbsp;</span>';
    }
    return out + ' ';
  }

  // `mode` is 'shown' on the initial row (squares render in color) and
  // 'spacer' on modifier rows (squares take width but are invisible).
  static renderDice(values, tn, dieSize, startingValue, mode) {
    const starting = DiceRenderer.renderStartingSquares(startingValue, mode || 'shown');
    if (!values || values.length === 0) {
      return '<span class="dice-placeholder">[ ' + starting + '&mdash; ]</span>';
    }
    const inner = values
      .map((v) => {
        if (v === null || v === undefined) {
          return '<span class="die empty">&nbsp;</span>';
        }
        return '<span class="die ' + DiceRenderer.dieClass(v, tn, dieSize) + '">' + v + '</span>';
      })
      .join(', ');
    return '[ ' + starting + inner + ' ]';
  }
}
