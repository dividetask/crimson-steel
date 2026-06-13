// Compendium keyword popups. Hover and keyboard focus reveal a keyword's
// definition via CSS; a click toggles a sticky open state so it works on
// touch and stays put. Mirrors the Character Sheet attribute popup.
(function () {
  document.addEventListener('click', function (e) {
    var kw = e.target.closest('.cr-kw');

    // Any click closes other open popups.
    document.querySelectorAll('.cr-kw.cr-kw-open').forEach(function (el) {
      if (el !== kw) el.classList.remove('cr-kw-open');
    });

    if (kw) {
      kw.classList.toggle('cr-kw-open');
      e.preventDefault();
    }
  });

  // Enter / Space opens the focused keyword; Escape closes it.
  document.addEventListener('keydown', function (e) {
    var kw = e.target.closest && e.target.closest('.cr-kw');
    if (!kw) return;
    if (e.key === 'Enter' || e.key === ' ') {
      kw.classList.toggle('cr-kw-open');
      e.preventDefault();
    } else if (e.key === 'Escape') {
      kw.classList.remove('cr-kw-open');
    }
  });
})();
