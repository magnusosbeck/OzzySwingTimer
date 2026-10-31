import {inPhase} from './windup-window.mjs';
const clamp = value => Math.max(0, Math.min(1, value));

// View only: uses the existing clock and never changes attacks or timing rules.
export function pendulumView(sim) {
  if (sim.phase === 'cooldown') {
    const duration = sim.config.interval - sim.config.wind;
    const progress = clamp(sim.progress / duration);
    return {phase: 'cooldown', fill: progress, cursor: 1 - progress, origin: 'right center',
      color: '#c1ed85', label: 'Weapon cooldown', direction: '←', remaining: Math.max(0, duration - sim.progress)};
  }
  if (sim.phase === 'wind') {
    const progress = clamp(sim.progress / sim.config.wind);
    return {phase: 'wind', fill: progress, cursor: progress, origin: 'left center',
      color: inPhase(sim) ? '#c1ed85' : '#ef6969', label: 'Auto Shot wind-up', direction: '→', remaining: Math.max(0, sim.config.wind - sim.progress)};
  }
  return {phase: 'blocked', fill: 1, cursor: 0, origin: 'right center',
    color: '#ff7777', label: 'Blocked', direction: 'Ⅱ', remaining: Math.max(0, sim.castLeft)};
}
