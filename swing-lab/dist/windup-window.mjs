// Wind-up says "press now" when every action started before it ends by the shot.
// Otherwise the player is out of phase and should let one Auto Shot pass untouched.
// A press during this wind-up (queued cast, its GCD) must not turn the bar red.
export function inPhase(sim) {
  if (sim.phase !== 'wind') return null;
  if (!sim.actionLocks?.length) return true;
  const origin = sim.t - sim.progress, end = origin + sim.config.wind;
  const ready = sim.actionLocks.reduce((time, lock) =>
    lock.start < origin - 1e-8 ? Math.max(time, lock.end) : time, 0);
  return ready <= end + 1e-8;
}

export function renderWindupStatus(sim) {
  const state = inPhase(sim);
  document.getElementById('hudWindupWindowValue').textContent =
    state === null ? '—' : state ? 'Tryck nu' : 'Ur fas';
  document.getElementById('hudWindupWindowHint').textContent =
    state === null ? 'Wind-up lyser grönt när det är dags att trycka.' :
    state ? 'Tryck Steady Shot nu. Den köas till skottet.' :
    'GCD hänger kvar över wind-up. Tryck inget, låt skottet gå orört.';
}
