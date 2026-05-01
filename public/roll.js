// Standalone Roll class for d10 dice pool checks. Mirrors the dice
// scoring used in views/combat_tracker.erb (10 = 2 successes, 1 = -1,
// other >= TN = 1 success) without the luck-reroll machinery, so any
// page that just needs to roll and paint a result can include this
// file alone.
(function() {
  function Roll(inputId, rollsId, dice, tn, signed) {
    this.inputId = inputId;
    this.rollsId = rollsId;
    this.dice = Math.max(0, dice | 0);
    this.tn = tn | 0;
    this.signed = !!signed;
    this.originalRolls = [];
  }
  Roll.registry = {};
  Roll.get = function(inputId) { return Roll.registry[inputId]; };
  Roll.rollOneDie = function() { return Math.floor(Math.random() * 10) + 1; };

  Roll.colorizeDie = function(d, tn) {
    var bg = null;
    if (d === 1) bg = '#e57373';
    else if (d === 10) bg = '#64b5f6';
    else if (d >= tn) bg = '#81c784';
    if (bg) return '<span style="background:' + bg + ';color:#000;padding:1px 6px;border-radius:3px;font-weight:bold;">' + d + '</span>';
    return '<span style="color:#777;">' + d + '</span>';
  };

  Roll.prototype.rollFresh = function() {
    this.originalRolls = [];
    for (var r = 0; r < this.dice; r++) this.originalRolls.push(Roll.rollOneDie());
    this.paint();
    return this.finalSuccesses();
  };

  Roll.prototype.successesIn = function(rolls) {
    var tn = this.tn, s = 0;
    for (var i = 0; i < rolls.length; i++) {
      var d = rolls[i];
      if (d === 10) s += 2;
      else if (d >= tn) s += 1;
      else if (d === 1) s -= 1;
    }
    return s;
  };

  Roll.prototype.finalSuccesses = function() { return this.successesIn(this.originalRolls); };

  Roll.prototype.paint = function() {
    var net = this.finalSuccesses();
    var inputEl = this.inputId ? document.getElementById(this.inputId) : null;
    if (inputEl) inputEl.value = this.signed ? net : Math.max(0, net);
    var rollsEl = this.rollsId ? document.getElementById(this.rollsId) : null;
    if (!rollsEl) return;
    var tn = this.tn;
    var colored = this.originalRolls.map(function(d) { return Roll.colorizeDie(d, tn); }).join(', ');
    rollsEl.innerHTML = 'Rolled: [' + colored + ']';
  };

  function rollDicePool(dice, tn, inputId, rollsId, signed) {
    var roll = new Roll(inputId, rollsId, dice, tn, signed);
    Roll.registry[inputId] = roll;
    roll.rollFresh();
    return roll;
  }

  window.Roll = Roll;
  window.rollDicePool = window.rollDicePool || rollDicePool;
})();
