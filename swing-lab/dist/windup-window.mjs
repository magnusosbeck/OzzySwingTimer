export function windupWindow(sim) {
  if (sim.phase !== 'wind' || !sim.config.queue || sim.config.mode !== 'blocking') return null;
  const origin = sim.t - sim.progress, end = origin + sim.config.wind;
  const ready = sim.actionLocks.reduce((time, lock) => Math.max(time, lock.end), origin);
  const start = Math.min(end, Math.max(origin, ready));
  const duration = Math.max(0, end - start);
  const fraction = Math.max(0, Math.min(1, duration / sim.config.wind));
  return {duration, fraction, left: 1 - fraction, total: sim.config.wind,
    inside: duration > 1e-8 && sim.t >= start - 1e-8 && sim.t <= end + 1e-8,
    open: duration > 1e-8 && sim.running && !sim.queued && !sim.moving &&
      sim.t >= start - 1e-8 && sim.castLeft <= 1e-8 && sim.gcdLeft <= 1e-8};
}

let previousTime = 0, lastWindow = null;
export function renderWindupWindow(sim, readouts = true) {
  if (sim.t < previousTime || sim.t === 0) lastWindow = null;
  previousTime = sim.t;
  const window = windupWindow(sim);
  if (window) lastWindow = window;
  const zone = document.getElementById('hudWindupWindow');
  zone.hidden = !window || window.duration < 1e-8;
  if (window) {
    zone.style.left = window.left * 100 + '%';
    zone.style.width = window.fraction * 100 + '%';
  }
  zone.classList.toggle('open', !!window?.open);
  if (!readouts) return;
  const label = document.getElementById('hudWindupWindowLabel');
  const value = document.getElementById('hudWindupWindowValue');
  const hint = document.getElementById('hudWindupWindowHint');
  label.textContent = window ? 'Köfönster i wind-up' : 'Senaste Köfönster';
  value.textContent = lastWindow ? Math.round(lastWindow.duration * 1000) + ' / ' +
    Math.round(lastWindow.total * 1000) + ' ms · ' + Math.round(lastWindow.fraction * 100) + ' %' : '—';
  hint.textContent = !sim.config.queue || sim.config.mode !== 'blocking' ? 'Köning är av i detta läge.' :
    !window ? 'Den turkosa zonen visas i pendelns snabba fas.' :
    sim.queued ? 'Cast köad till nästa Auto Shot.' :
    !window.duration ? 'Action lock blockerar hela wind-up.' :
    window.open ? 'Tryck i den turkosa zonen för att köa nästa cast.' :
    'Turkost visar delen efter att Action lock har släppt.';
}
