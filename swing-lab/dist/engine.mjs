// Experimental rules, independent of any specific WoW client.
// Fixed 1 ms steps keep timing comparisons independent of browser frame rate.
const EPS = 1e-8;
export class Simulation {
  constructor(config = {}) {
    // gcdStart 'press': a cast queued in wind-up starts its GCD at the press (measured in TBC 2.5.6).
    this.config = {interval: 2.8, wind: 0.5, duration: 1.5, gcd: 1, gcdStart: 'cast', breakEven: 1.3, mode: 'blocking', queue: true,
      autoCast: false, castOffset: 0, autoInstant: false, instantOffset: .6, warmup: false, ...config};
    this.reset();
  }
  reset() {
    Object.assign(this, {t: 0, accumulator: 0, running: false, moving: false, phase: 'wind',
      progress: 0, castLeft: 0, gcdLeft: 0, gcdSource: null, gcdShot: null, queued: false, shots: 0, spells: 0, instants: 0,
      delay: null, totalDelay: 0, expected: this.config.wind, lastRelease: null, dpsSample: null,
      castFinishedAt: null, measurementStart: null, actionLocks: [], queueAcceptCount: 0,
      autoAttempted: false, instantAttempted: false,
      lastInstantAt: null, releaseBefore: null, delayWorthIt: false, autoMisses: 0, instantMisses: 0,
      events: [], eventVersion: (this.eventVersion ?? 0) + 1,
      message: 'Starta simuleringen. Första Auto Shot börjar med en uppdragning.'});
  }
  log(text) {
    this.eventVersion++;
    this.events.unshift({t: this.t, text});
    this.events.length = Math.min(30, this.events.length);
  }
  get damage() { return (this.shots + this.spells + this.instants) * 10; }
  get dps() { return this.t > 0 ? this.damage / this.t : 0; }
  get autoOnlyDamage() {
    return this.t + EPS < this.config.wind ? 0 :
      (1 + Math.floor((this.t - this.config.wind + EPS) / this.config.interval)) * 10;
  }
  get currentDelay() {
    if (this.phase === 'cooldown') return 0;
    const earliest = this.t + (this.phase === 'wind' ? this.config.wind - this.progress : this.config.wind);
    return Math.max(0, earliest - this.expected);
  }
  get clipping() { return this.totalDelay + this.currentDelay; }
  recordActionLock(kind, duration) {
    this.actionLocks.push({kind, start: this.t, end: this.t + duration});
    if (this.actionLocks.length > 32) this.actionLocks.shift();
  }
  startGcd() {
    this.gcdLeft = this.config.gcd;
    this.gcdSource = 'cast';
    this.gcdShot = this.shots;
  }
  startCast(fromQueue = false) {
    this.castLeft = this.config.duration;
    // A queued press may already have started its GCD.
    if (!(fromQueue && this.config.gcdStart === 'press')) this.startGcd();
    this.recordActionLock('cast', Math.max(this.config.duration, this.gcdLeft));
    this.log('Steady Shot startar');
    this.message = 'Steady Shot pågår.';
  }
  reportBlockedAttempt(kind, windOnly = false) {
    // Optional diagnostics for previews; never reschedules or changes an attempt.
    if (typeof this.config.onBlockedAttempt !== 'function') return;
    const queuedWait = this.queued ? Math.max(0, this.config.wind - this.progress) +
      Math.max(this.config.duration, this.config.gcd) : 0;
    const remaining = windOnly ? Math.max(0, this.config.wind - this.progress) :
      Math.max(this.castLeft, this.gcdLeft, queuedWait);
    const reason = windOnly ? 'uppdragningen' : this.queued ? 'en köad cast' :
      this.gcdLeft >= this.castLeft ? 'GCD' : 'en pågående cast';
    this.config.onBlockedAttempt({kind, reason, remaining, time: this.t,
      shots: this.shots, cycleStart: this.lastRelease,
      carry: reason === 'GCD' && this.gcdShot < this.shots});
  }
  pressCast() {
    if (!this.running) { this.message = 'Starta eller fortsätt simuleringen först.'; return false; }
    if (this.moving) { this.message = 'Stanna innan du kastar.'; return false; }
    if (this.castLeft > EPS || this.gcdLeft > EPS || this.queued) {
      this.reportBlockedAttempt('cast');
      this.message = 'Vänta tills cast, kö och GCD är klara.'; return false;
    }
    if (this.phase === 'wind' && this.config.mode === 'blocking') {
      if (this.config.queue) {
        this.log('Spell köad efter Auto Shot'); this.queued = true;
        this.queueAcceptCount++;
        if (this.config.gcdStart === 'press') this.startGcd();
        this.message = 'Spell köad — Auto Shot får bli klart först.'; return true;
      }
      this.message = 'Cast avvisad under uppdragningen i denna försöksregel.';
      this.reportBlockedAttempt('cast', true);
      return false;
    }
    this.startCast();
    return true;
  }
  pressInstant() {
    if (!this.running) { this.message = 'Starta eller fortsätt simuleringen först.'; return false; }
    if (this.castLeft > EPS || this.gcdLeft > EPS || this.queued) {
      this.reportBlockedAttempt('instant');
      this.message = 'Arcane Shot avvisad: cast, kö eller GCD är inte klar.'; return false;
    }
    this.instants++;
    this.lastInstantAt = this.t;
    this.gcdLeft = this.config.gcd;
    this.gcdSource = 'instant';
    this.gcdShot = this.shots;
    this.recordActionLock('instant', this.config.gcd);
    this.log('Arcane Shot träffar · 10 skada · Ny GCD');
    this.message = 'Arcane Shot träffar direkt och startar en ny GCD.';
    return true;
  }
  toggleMove() {
    if (!this.running) { this.message = 'Starta eller fortsätt simuleringen först.'; return; }
    this.moving = !this.moving;
    this.log(this.moving ? 'Rörelse börjar' : 'Rörelse slutar');
    if (this.moving) {
      if (this.castLeft > 0) {
        this.castLeft = 0;
        const lock = this.actionLocks.at(-1);
        if (lock?.kind === 'cast') lock.end = Math.min(lock.end, this.t + this.gcdLeft);
        this.log('Cast avbruten av rörelse');
      }
      this.queued = false;
      if (this.phase === 'wind') {
        this.phase = 'blocked'; this.progress = 0; this.log('Uppdragning avbruten av rörelse');
      }
    }
    this.message = this.moving ? 'Du rör dig. Uppdragningen kan inte slutföras.' : 'Du står still.';
  }
  attemptAutomaticCast() {
    if (this.lastRelease === null) return;
    const target = this.lastRelease + this.config.castOffset * this.config.interval;
    if (this.config.autoCast && !this.autoAttempted && this.t + EPS >= target) {
      this.autoAttempted = true;
      this.log('Automatiskt kastförsök');
      if (!this.pressCast()) { this.autoMisses++; this.log('Automatiskt kastförsök avvisat'); }
    }
    const instantTarget = this.lastRelease + this.config.instantOffset * this.config.interval;
    if (this.config.autoInstant && !this.instantAttempted && this.t + EPS >= instantTarget) {
      this.instantAttempted = true;
      if (!this.pressInstant()) {
        this.autoMisses++; this.instantMisses++; this.log('Automatisk Arcane Shot avvisad');
      }
    }
  }
  advance(dt) {
    if (!this.running) return;
    this.accumulator += dt;
    while (this.accumulator + EPS >= 0.001) { this.step(0.001); this.accumulator -= 0.001; }
  }
  step(dt) {
    this.attemptAutomaticCast();
    this.t += dt;
    const wasCasting = this.castLeft > EPS;
    this.castLeft = Math.max(0, this.castLeft - dt);
    this.gcdLeft = Math.max(0, this.gcdLeft - dt);
    if (this.castLeft < EPS) this.castLeft = 0;
    if (this.gcdLeft < EPS) this.gcdLeft = 0;
    if (wasCasting && !this.castLeft) {
      this.spells++; this.castFinishedAt = this.t; this.log('Spell träffar · 10 skada');
    }
    const blocked = this.moving || (this.config.mode === 'blocking' && this.castLeft > 0);
    if (this.phase === 'cooldown') {
      this.progress += dt;
      if (this.progress + EPS >= this.config.interval - this.config.wind) {
        this.progress = 0; this.phase = blocked ? 'blocked' : 'wind';
      }
    } else if (this.phase === 'blocked') {
      if (!blocked) { this.phase = 'wind'; this.progress = 0; }
    } else if (this.phase === 'wind') {
      if (blocked) { this.phase = 'blocked'; this.progress = 0; return; }
      this.progress += dt;
      if (this.progress + EPS >= this.config.wind) {
        // 100% means an attempt at the end of wind-up, just before release.
        this.attemptAutomaticCast();
        this.shots++;
        this.delay = Math.max(0, this.t - this.expected);
        if (this.delay < EPS) this.delay = 0;
        this.totalDelay += this.delay;
        // An instant's GCD often costs time only in the following cycle: look back two releases.
        const since = this.releaseBefore ?? this.lastRelease ?? -Infinity;
        this.delayWorthIt = this.delay > EPS && this.lastInstantAt !== null &&
          this.lastInstantAt > since && this.delay <= this.config.breakEven;
        this.log('Auto Shot · 10 skada' + (this.delay > 0.001 ? ' · +' + this.delay.toFixed(3) + ' s' : ''));
        // The tenth Auto Shot is the anchor; its damage belongs to warm-up.
        // Damage after this instant is measured through complete release cycles.
        if (this.config.warmup && this.shots === 10) {
          this.measurementStart = {time: this.t, damage: this.damage};
        }
        // Capture at the exact release boundary, independent of render timing.
        // The opening wind-up is not a full shot-to-shot cycle.
        if (this.shots >= 2) {
          // Negative: this cycle's actual shot delay. Positive: spare time
          // between the last completed blocking cast and planned wind-up.
          const hasCast = this.castFinishedAt !== null && this.config.mode === 'blocking';
          const margin = this.delay > EPS ? -this.delay : hasCast ?
            Math.max(0, this.expected - this.config.wind - this.castFinishedAt) : 0;
          const elapsed = this.config.warmup ?
            (this.measurementStart ? this.t - this.measurementStart.time : 0) : this.t;
          const damage = this.config.warmup ?
            (this.measurementStart ? this.damage - this.measurementStart.damage : 0) : this.damage;
          const referenceDamage = this.config.warmup ?
            Math.floor((elapsed + EPS) / this.config.interval) * 10 : this.autoOnlyDamage;
          this.dpsSample = {dps: elapsed > EPS ? damage / elapsed : null,
            baseline: elapsed > EPS ? referenceDamage / elapsed : null,
            ratio: referenceDamage > 0 ? damage / referenceDamage : null,
            time: this.t, elapsed, margin,
            marginNote: this.delay > EPS ? 'Auto Shot fördröjdes denna cykel' : hasCast ?
              'Tid till godo före uppdragningen' : this.config.mode === 'parallel' ?
                'Parallella casts blockerar inte uppdragningen' : 'Ingen avslutad cast denna cykel'};
        }
        this.expected = this.t + this.config.interval;
        this.releaseBefore = this.lastRelease;
        this.lastRelease = this.t; this.autoAttempted = false; this.instantAttempted = false; this.castFinishedAt = null;
        this.phase = 'cooldown'; this.progress = 0;
        if (this.queued) { this.queued = false; this.startCast(true); }
        this.attemptAutomaticCast();
      }
    }
  }
  prediction() {
    if (this.config.mode === 'parallel' || this.queued) return 0;
    if (this.phase === 'wind' && !this.castLeft) return this.config.queue ? 0 : null;
    const available = this.phase === 'cooldown' ?
      Math.max(0, this.config.interval - this.config.wind - this.progress) : 0;
    return Math.max(0, (this.castLeft || this.config.duration) - available);
  }
}
