// The DM's notice in the top bar of every DM page (views/_dm_notices.erb):
// what the players are waiting on, with Approve / Cancel / Dismiss.
//
// This page's one live-updates connection (GET /encounter/events,
// docs/project/live_updates.md) lives here: on every "changed" the notice is
// fetched again, and `live:changed` is fired for the rest of the page (the
// Encounter page's builders and Player actions panel listen for it).
const SEL = '#dm-notices';
let open = false;

function refresh() {
  fetch('/dm/notices', { headers: { Accept: 'text/html' } })
    .then((r) => (r.ok ? r.text() : null))
    .then((html) => {
      const cur = document.querySelector(SEL);
      if (html == null || !cur) return;
      if (cur.contains(document.activeElement) && document.activeElement !== document.body) return;
      const tmp = document.createElement('div');
      tmp.innerHTML = html.trim();
      const next = tmp.querySelector(SEL);
      if (!next || next.outerHTML === cur.outerHTML) return;
      cur.replaceWith(next);
      const list = next.querySelector('.dm-notices-list');
      if (list) list.hidden = !open;
    })
    .catch(() => {});
}

document.addEventListener('click', (e) => {
  const b = e.target.closest && e.target.closest('.dm-notices-btn');
  if (b) {
    open = !open;
    const list = document.querySelector(SEL + ' .dm-notices-list');
    if (list) list.hidden = !open;
    return;
  }
  // Click elsewhere closes it.
  if (open && !(e.target.closest && e.target.closest(SEL))) {
    open = false;
    const list = document.querySelector(SEL + ' .dm-notices-list');
    if (list) list.hidden = true;
  }
});

if (document.querySelector(SEL) && window.EventSource) {
  const es = new EventSource('/encounter/events');
  es.addEventListener('changed', () => {
    refresh();
    document.dispatchEvent(new CustomEvent('live:changed'));
  });
}
