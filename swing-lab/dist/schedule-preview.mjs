import {Simulation} from './engine.mjs';

// Run the existing model, without changing the user's offsets or retrying casts.
// Discard opening cycles and inspect several repetitions to catch alternating failures.
export function schedulePreview(config, includeInstant = true) {
  const blocked = [];
  const sim = new Simulation({...config, autoCast: true, autoInstant: includeInstant, warmup: false,
    onBlockedAttempt: attempt => {
      if (attempt.shots >= 3 && attempt.cycleStart !== null) blocked.push(attempt);
    }});
  sim.running = true;
  const limit = 12 * Math.max(config.interval, config.duration + config.wind, config.gcd);
  while (sim.shots < 10 && sim.t < limit) sim.advance(.01);
  const issues = [];
  for (const kind of ['cast', 'instant']) {
    const attempts = blocked.filter(a => a.kind === kind);
    if (!attempts.length) continue;
    const worst = attempts.reduce((a, b) => a.remaining > b.remaining ? a : b);
    // Multiple repeated failures are the same conflict, not additive cooldowns.
    const offset = kind === 'cast' ? config.castOffset : config.instantOffset;
    const start = Math.max(0, Math.min(1, offset)) * config.interval;
    const end = start + Math.min(worst.remaining, config.interval);
    const segments = [];
    for (let cycle = Math.floor(start / config.interval); cycle * config.interval < end - 1e-8; cycle++) {
      const origin = cycle * config.interval;
      const a = Math.max(start, origin), b = Math.min(end, origin + config.interval);
      if (b > a + 1e-8) segments.push({start: a - origin, duration: b - a});
    }
    issues.push({kind, reason: worst.reason, remaining: worst.remaining,
      carry: worst.carry, segments});
  }
  return {issues, valid: issues.length === 0};
}
