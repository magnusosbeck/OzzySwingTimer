// Planning aid for queueing the next cast at an undelayed Auto Shot release.
// Assumes the proposed casts/instant execute. Conflict warnings remain separate.
export function queueWindow(config, includeInstant = true) {
  const end = config.interval, windStart = end - config.wind;
  if (config.mode !== 'blocking' || !config.queue) {
    return {available: false, start: end, end, duration: 0, reason: 'disabled'};
  }
  const press = Math.max(0, Math.min(1, config.castOffset)) * end;
  // A cast queued in the preceding wind-up starts at this cycle's beginning.
  const castStart = press >= windStart - 1e-8 ? 0 : press;
  const castEnd = castStart + config.duration;
  if (castEnd > windStart + 1e-8) {
    return {available: false, start: end, end, duration: 0, reason: 'clipping'};
  }
  // With gcdStart 'press', a queued cast's GCD began at the press in the preceding wind-up.
  const gcdStart = press >= windStart - 1e-8 && config.gcdStart === 'press' ? press - end : castStart;
  const instantEnd = includeInstant ? Math.max(0, Math.min(1, config.instantOffset)) * end + config.gcd : 0;
  const ready = Math.max(castEnd, gcdStart + config.gcd, instantEnd);
  const start = Math.min(end, Math.max(windStart, ready));
  const duration = Math.max(0, end - start);
  return {available: duration > 1e-8, start, end, duration,
    reason: duration > 1e-8 ? 'open' : 'blocked', overrun: Math.max(0, ready - end)};
}
