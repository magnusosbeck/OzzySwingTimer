// Accepted actions only; projected lock duration is max(cast time, GCD).
// Geometry mirrors the cooldown phase of the pendulum (time runs right to left).
export function actionBudget(sim) {
  const cooldown = sim.config.interval - sim.config.wind;
  const busy = Math.max(sim.castLeft, sim.gcdLeft);
  const show = sim.lastRelease !== null && sim.phase !== 'wind';
  const origin = sim.lastRelease ?? sim.t;
  const deadline = origin + cooldown;
  const segments = show ? sim.actionLocks.flatMap(lock => {
    const a = Math.max(origin, lock.start), b = Math.min(deadline, lock.end);
    if (b <= a + 1e-8) return [];
    return [{kind: lock.kind, left: Math.max(0, 1 - (b - origin) / cooldown),
      width: (b - a) / cooldown, duration: b - a}];
  }) : [];
  const free = sim.phase === 'cooldown' ? Math.max(0, deadline - sim.t - busy) : 0;
  const castCost = Math.max(sim.config.duration, sim.config.gcd);
  const assess = sim.phase === 'cooldown' && !sim.moving && !sim.queued;
  return {segments, busy, free, assess, castCost, instantCost: sim.config.gcd,
    fitsCast: assess && free + 1e-8 >= castCost,
    fitsInstant: assess && free + 1e-8 >= sim.config.gcd,
    overflow: show ? Math.max(0, sim.t + busy - deadline) : 0};
}
