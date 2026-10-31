// Projection of one accepted cast onto planned weapon-cooldown windows.
// Queueing consumes no cast time. This is a preview, not a cast/GCD scheduler.
export function castPreview({interval, wind, duration, castOffset, mode, queue}) {
  const wait = interval - wind;
  const press = Math.max(0, Math.min(1, castOffset)) * interval;
  const inWind = press >= wait - 1e-8;
  const queued = mode === 'blocking' && inWind && queue;
  if (mode === 'blocking' && inWind && !queue) {
    return {segments: [], visible: 0, overflow: 0, queued: false, rejected: true};
  }
  const start = queued ? interval : press, end = start + duration;
  const segments = [];
  let overflow = 0;
  if (mode === 'blocking') {
    const cycle = queued ? 1 : 0, origin = cycle * interval;
    const visibleEnd = Math.min(end, origin + wait);
    if (visibleEnd > start) segments.push({cycle, start: start - origin, duration: visibleEnd - start});
    // A blocking cast delays the shot, rather than continuing through its wind-up.
    overflow = Math.max(0, end - (origin + wait));
  } else {
    // Parallel casts can overlap wind-up; only their cooldown intersections are colored.
    for (let cycle = Math.floor(start / interval); cycle * interval < end; cycle++) {
      const origin = cycle * interval;
      const a = Math.max(start, origin), b = Math.min(end, origin + wait);
      if (b > a + 1e-8) segments.push({cycle, start: a - origin, duration: b - a});
    }
  }
  return {segments, visible: segments.reduce((sum, s) => sum + s.duration, 0), overflow, queued, rejected: false};
}

// GCD follows the accepted cast start and can continue across wind-up/release.
// Unlike cast shading, it is projected across the entire nominal shot cycle.
export function gcdPreview(config) {
  const cast = castPreview(config), duration = config.gcd ?? 1, segments = [];
  if (cast.rejected) return {segments, duration, queued: false, rejected: true};
  const start = cast.queued ? config.interval :
    Math.max(0, Math.min(1, config.castOffset)) * config.interval;
  const end = start + duration;
  for (let cycle = Math.floor(start / config.interval); cycle * config.interval < end - 1e-8; cycle++) {
    const origin = cycle * config.interval;
    const a = Math.max(start, origin), b = Math.min(end, origin + config.interval);
    if (b > a + 1e-8) segments.push({cycle, start: a - origin, duration: b - a});
  }
  return {segments, duration, queued: cast.queued, rejected: false};
}
