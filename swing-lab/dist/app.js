import {Simulation} from './engine.mjs';
import {castPreview, gcdPreview} from './cast-preview.mjs';
import {schedulePreview} from './schedule-preview.mjs';
import {queueWindow} from './queue-window.mjs';
import {pendulumView} from './pendulum-view.mjs';
import {actionBudget} from './action-budget.mjs';
import {renderWindupWindow} from './windup-window.mjs';
const elements = new Map();
const $ = id => {
  if (!elements.has(id)) elements.set(id, document.getElementById(id));
  return elements.get(id);
};
// Avoid replacing text nodes when the visible value has not changed.
function text(id, value) {
  const node = $(id), next = String(value);
  if (node.textContent !== next) node.textContent = next;
}
const sim = new Simulation();
// Measured in TBC Anniversary 2.5.6 (docs/timing-design.md); prototype = the original dummy values.
const PRESETS = {
  measured: {interval: 2.29, wind: 0.36, gcd: 1.5, duration: 1.11, instantCooldown: 6, gcdStart: 'press'},
  prototype: {interval: 2.8, wind: 0.5, gcd: 1, duration: 1.5, instantCooldown: 0, gcdStart: 'cast'}
};
let selectedHandle = 'cast';
const number = (n, digits = 2) => n.toFixed(digits).replace('.', ',');
const format = (n, digits = 2) => number(n, digits) + ' s';
const rows = [
  ['cycle', 'Auto Shot cycle', '#b9d597', 'Weapon cooldown och Auto Shot wind-up bildar hela cykeln.'],
  ['cooldown', 'Weapon cooldown', '#c1ed85', 'Rörelse är möjlig. En blockerande cast måste hinna bli klar.'],
  ['wind', 'Auto Shot wind-up', '#edbd70', 'Stå still. Auto Shot avfyras när den här mätaren fyllts.'],
  ['spell', 'Steady Shot cast', '#91b9ee', 'Steady Shots casttid, separat från Auto Shot och Global cooldown.'],
  ['gcd', 'Global cooldown', '#b69bd9', 'En egen timer för när nästa spell kan påbörjas.']
];
$('timers').innerHTML = rows.map(([id, title, color, hint]) => `<div class="timer" style="--color:${color}"><div class="timerHead"><span id="${id}Title">${title}</span><span id="${id}Text">—</span></div><div class="track" role="progressbar" aria-label="${title}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" id="${id}Track"><div id="${id}Fill" class="fill"></div></div><small>${hint}</small></div>`).join('');
let updateReadouts = true;
let hudLockKey = '';
let lastQueueAcceptCount = 0, queueFlash = null;
function bar(id, value, label) {
  value = Math.max(0, Math.min(1, value));
  const fill = $(id + 'Fill'), transform = `scaleX(${value})`;
  if (fill.style.transform !== transform) fill.style.transform = transform;
  if (updateReadouts) {
    const track = $(id + 'Track'), percent = String(Math.round(value * 100));
    if (track.getAttribute('aria-valuenow') !== percent) track.setAttribute('aria-valuenow', percent);
    text(id + 'Text', label);
  }
}
function render(readouts = true) {
  updateReadouts = readouts;
  const pendulum = pendulumView(sim);
  const fill = $('pendulumFill'), cursor = $('pendulumCursor');
  fill.style.transform = `scaleX(${pendulum.fill})`;
  fill.style.transformOrigin = pendulum.origin;
  fill.style.background = pendulum.color;
  cursor.style.transform = `translateX(${pendulum.cursor * 100}%)`;
  renderWindupWindow(sim, readouts);
  if (sim.queueAcceptCount > lastQueueAcceptCount) {
    queueFlash?.cancel();
    queueFlash = $('pendulumTrack').animate([
      {outlineWidth:'4px',outlineColor:'rgba(103,255,145,1)',boxShadow:'0 0 18px rgba(103,255,145,.8)'},
      {outlineWidth:'4px',outlineColor:'rgba(103,255,145,.9)',boxShadow:'0 0 12px rgba(103,255,145,.5)',offset:.2},
      {outlineWidth:'4px',outlineColor:'rgba(103,255,145,0)',boxShadow:'0 0 0 rgba(103,255,145,0)'}
    ], {duration:350,easing:'ease-out'});
  } else if (sim.queueAcceptCount < lastQueueAcceptCount) {
    queueFlash?.cancel();
  }
  lastQueueAcceptCount = sim.queueAcceptCount;
  if (readouts) {
    const budget = actionBudget(sim);
    const lockKey = JSON.stringify(budget.segments);
    if (lockKey !== hudLockKey) {
      hudLockKey = lockKey;
      $('pendulumLocks').replaceChildren(...budget.segments.map(segment => {
        const region = document.createElement('div');
        region.className = 'pendulum-lock-region';
        region.style.left = segment.left * 100 + '%';
        region.style.width = segment.width * 100 + '%';
        region.title = (segment.kind === 'cast' ? 'Steady Shot cast + GCD' : 'Arcane Shot + GCD') + ' · ' + format(segment.duration);
        return region;
      }));
    }
    text('hudLockTime', format(budget.busy));
    text('hudFreeTime', budget.assess ? format(budget.free) : '—');
    text('hudFitCast', 'Cast + GCD · ' + (budget.assess ? budget.fitsCast ? 'Ryms' : 'Ryms inte' : '—'));
    text('hudFitInstant', 'Arcane Shot + GCD · ' + (budget.assess ? budget.fitsInstant ? 'Ryms' : 'Ryms inte' : '—'));
    $('hudFitCast').classList.toggle('fits', budget.fitsCast);
    $('hudFitInstant').classList.toggle('fits', budget.fitsInstant);
    text('hudBudgetNote', sim.queued ? 'Spell köad — Action lock börjar vid nästa avfyrning.' :
      sim.phase === 'wind' ? 'Auto Shot wind-up. Nästa Weapon cooldown visas efter avfyrningen.' :
      sim.phase === 'blocked' ? 'Uppdragningen är blockerad. Väntar på att den kan börja.' :
      'Efter nuvarande spärr, helt före wind-up.' +
      (budget.overflow > 1e-8 ? ' Action lock går ' + format(budget.overflow) + ' över kanten.' : '') +
      ' GCD kan fortsätta under wind-up utan att i sig stoppa Auto Shot.');
    text('pendulumPhase', pendulum.label);
    text('pendulumRemaining', pendulum.phase === 'blocked' && !pendulum.remaining ? 'Väntar' : format(pendulum.remaining));
    text('pendulumDirection', pendulum.direction);
    text('pendulumStatus', !sim.running ? sim.t ? 'Pausad' : 'Starta simuleringen' :
      pendulum.phase === 'blocked' ? 'Väntar på att hindret släpper' :
        pendulum.phase === 'wind' ? 'Snabb fas · stå still' : 'Långsam fas');
    $('pendulumTrack').setAttribute('aria-valuenow', Math.round(pendulum.fill * 100));
    $('pendulumTrack').setAttribute('aria-valuetext', pendulum.label + ', ' + format(pendulum.remaining) + ' kvar');
  }
  const c = sim.config, cd = c.interval - c.wind;
  bar('cooldown', sim.phase === 'cooldown' ? sim.progress / cd : sim.shots ? 1 : 0,
    sim.phase === 'cooldown' ? format(Math.max(0, cd - sim.progress)) + ' kvar' : 'Väntar');
  bar('wind', sim.phase === 'wind' ? sim.progress / c.wind : 0,
    sim.phase === 'wind' ? format(Math.max(0, c.wind - sim.progress)) : sim.phase === 'blocked' ? 'Blockerad' : 'Väntar');
  bar('cycle', sim.phase === 'cooldown' ? sim.progress / c.interval : sim.phase === 'wind' ?
    (sim.shots ? cd + sim.progress : sim.progress) / c.interval : cd / c.interval,
    sim.phase === 'cooldown' ? 'Weapon cooldown' : sim.phase === 'wind' ? 'Auto Shot wind-up' : 'Blockerad');
  bar('spell', sim.castLeft ? 1 - sim.castLeft / c.duration : 0,
    sim.castLeft ? format(sim.castLeft) : sim.queued ? 'Köad' : 'Ingen cast');
  bar('gcd', sim.gcdLeft ? 1 - sim.gcdLeft / c.gcd : 0, sim.gcdLeft ? format(sim.gcdLeft) : 'Redo');
  if (!readouts) return;
  text('gcdTitle', 'Global cooldown' + (sim.gcdLeft && sim.gcdSource === 'instant' ? ' · Arcane Shot' : '') + ' · ' + format(c.gcd));
  $('gcdFill').style.background = sim.gcdSource === 'instant' ? '#f0a35a' : '#b69bd9';
  text('clock', format(sim.t));
  text('status', sim.running ? 'Körs' : 'Pausad');
  $('statusDot').classList.toggle('running', sim.running);
  text('play', sim.running ? 'Pausa' : sim.t ? 'Fortsätt' : 'Starta');
  text('dps', sim.dpsSample?.dps != null ? number(sim.dpsSample.dps) : '—');
  const margin = sim.dpsSample?.margin;
  // Round the sign and color together so sub-display precision cannot show red zero.
  const roundedMargin = margin === undefined ? null : Math.round(margin * 1000) / 1000;
  text('cycleMargin', roundedMargin === null ? '—' :
    (roundedMargin < 0 ? '−' : roundedMargin > 0 ? '+' : '') + format(Math.abs(roundedMargin), 3));
  $('cycleMargin').classList.toggle('is-clipped', roundedMargin !== null && roundedMargin < 0);
  $('cycleMargin').classList.toggle('is-safe', roundedMargin !== null && roundedMargin >= 0);
  text('marginNote', sim.dpsSample?.marginNote ?? 'Visas efter första hela skottcykeln');
  const sample = sim.dpsSample;
  text('warmupStatus', sim.config.warmup ? sim.shots < 10 ?
    'Uppvärmning · ' + sim.shots + ' / 10 Auto Shots' : sample?.dps != null ?
      'Uppvärmning klar · Mättid ' + format(sample.elapsed) :
      'Uppvärmning klar · Väntar på första hela mätcykeln' : 'Uppvärmning av · Mätning från start');
  text('baseline', sample?.dps != null ? 'Mättid vid senaste cykelslut: ' + format(sample.elapsed) + ' · Enbart ostörda Auto Shots ' +
    number(sample.baseline) + ' DPS · Din skada: ' + number(sample.ratio) + '× referensen.' :
    sim.config.warmup ? 'DPS visas efter 10 Auto Shots och en hel mätcykel.' :
      'DPS visas efter första hela skottcykeln och uppdateras vid varje avslutad cykel.');
  text('attempts', sim.autoMisses + ' avvisade · ' + sim.instantMisses + ' Arcane Shot');
  text('feedback', sim.message);
}
$('play').onclick = () => {
  sim.running = !sim.running;
  sim.message = sim.running ? 'Simuleringen körs. Tryck 1 för Steady Shot eller 2 för Arcane Shot.' : 'Simuleringen är pausad.';
  render();
};
$('reset').onclick = () => { sim.reset(); render(); };
$('cast').onclick = () => { sim.pressCast(); render(); };
$('instant').onclick = () => { sim.pressInstant(); render(); };
function selectHandle(kind) {
  selectedHandle = kind;
  $('selectCast').setAttribute('aria-pressed', String(kind === 'cast'));
  $('selectInstant').setAttribute('aria-pressed', String(kind === 'instant'));
  $('castOffset').classList.toggle('selected-handle', kind === 'cast');
  $('instantOffset').classList.toggle('selected-handle', kind === 'instant');
  const percent = Number($(kind === 'cast' ? 'castOffset' : 'instantOffset').value);
  text('offsetValue', (kind === 'cast' ? 'Steady Shot: ' : 'Arcane Shot: ') +
    format(percent / 100 * sim.config.interval, 3) + ' · ' + number(percent, 1) + '%');
}
$('selectCast').onclick = () => selectHandle('cast');
$('selectInstant').onclick = () => selectHandle('instant');
for (const [id, kind] of [['castOffset', 'cast'], ['instantOffset', 'instant']]) {
  $(id).addEventListener('pointerdown', () => selectHandle(kind));
  $(id).addEventListener('focus', () => selectHandle(kind));
}
function settings() {
  for (const id of ['interval', 'wind', 'gcd', 'duration', 'instantCooldown']) {
    sim.config[id] = Number($(id).value); $(id + 'Value').textContent = format(sim.config[id]);
  }
  sim.config.mode = $('mode').value;
  sim.config.gcdStart = $('gcdStart').value;
  text('cycleTitle', 'Auto Shot cycle · ' + format(sim.config.interval));
  text('cooldownTitle', 'Weapon cooldown · ' + format(sim.config.interval - sim.config.wind));
  text('windTitle', 'Auto Shot wind-up · ' + format(sim.config.wind));
  text('spellTitle', 'Steady Shot cast · ' + format(sim.config.duration));
  text('cycleSummary', 'Weapon cooldown ' + format(sim.config.interval - sim.config.wind) +
    ' + Auto Shot wind-up ' + format(sim.config.wind) + ' = Auto Shot cycle ' + format(sim.config.interval) + '.');
  text('gcdTitle', 'Global cooldown · ' + format(sim.config.gcd));
  text('gcdPreviewTitle', 'GCD · Steady Shot · ' + format(sim.config.gcd));
  text('instantGcdTitle', 'GCD · Arcane Shot · ' + format(sim.config.gcd));
  sim.config.queue = $('queue').checked;
  sim.config.autoCast = $('autoCast').checked;
  sim.config.autoInstant = $('autoCast').checked && $('includeInstant').checked;
  sim.config.warmup = $('warmup').checked;
  text('dpsExplanation', sim.config.warmup ?
    'De första 10 Auto Shots och all skada fram till den tionde avfyrningen räknas bort. Därefter mäts DPS mellan hela skottcykler och hålls stilla däremellan.' :
    'DPS är genomsnittet från start till senaste avslutade cykel, inklusive första uppdragningen. Värdet hålls stilla mellan cyklerna.');
  sim.config.castOffset = Number($('castOffset').value) / 100;
  sim.config.instantOffset = Number($('instantOffset').value) / 100;
  text('castOffsetLabel', format(sim.config.castOffset * sim.config.interval, 3));
  text('instantOffsetLabel', format(sim.config.instantOffset * sim.config.interval, 3));
  selectHandle(selectedHandle);
  $('autoMarker').style.left = sim.config.castOffset * 100 + '%';
  $('instantMarker').style.left = sim.config.instantOffset * 100 + '%';
  const windPercent = sim.config.wind / sim.config.interval * 100;
  $('waitBand').style.width = (100 - windPercent) + '%';
  $('waitBandText').textContent = 'Weapon cooldown · ' + format(sim.config.interval - sim.config.wind);
  $('windBand').style.width = windPercent + '%';
  const preview = castPreview(sim.config), wait = sim.config.interval - sim.config.wind;
  $('castPreview').replaceChildren(...preview.segments.map(segment => {
    const region = document.createElement('div');
    region.className = 'cast-region';
    region.style.left = (segment.start / wait * 100) + '%';
    region.style.width = (segment.duration / wait * 100) + '%';
    region.title = format(segment.duration) + (segment.cycle > 0 ? ' i nästa vapenväntan' : ' i denna vapenväntan');
    return region;
  }));
  text('castPreviewText', preview.rejected ? 'Ingen cast: köning är av och trycket ligger under uppdragningen.' :
    'Cast i vapenväntan: ' + format(preview.visible) +
    (preview.queued ? ' · Hela casten börjar i nästa vapenväntan.' :
      preview.segments.some(s => s.cycle > 0) ? ' · Återstående cast visas i nästa vapenväntan.' : '') +
    (preview.overflow > 1e-8 ? ' · ' + format(preview.overflow) + ' går över den planerade vapenväntan och fördröjer skottet.' : ''));
  const gcd = gcdPreview(sim.config);
  $('gcdWindBoundary').style.left = (100 - windPercent) + '%';
  $('gcdPreview').replaceChildren(...gcd.segments.map(segment => {
    const region = document.createElement('div');
    region.className = 'gcd-region';
    region.style.left = (segment.start / sim.config.interval * 100) + '%';
    region.style.width = (segment.duration / sim.config.interval * 100) + '%';
    return region;
  }));
  text('gcdPreviewText', gcd.rejected ? 'Ingen GCD: kastförsöket avvisas under uppdragningen.' :
    'Lila: ' + format(gcd.duration) + ' GCD ' +
    (gcd.queued && sim.config.gcdStart === 'press' ? 'från knapptrycket i wind-up; casten börjar vid skottet.' :
      'från faktisk caststart' + (gcd.queued ? ' i nästa vapenväntan.' : '. GCD kan fortsätta under uppdragningen.')) +
    (!gcd.queued && gcd.segments.some(s => s.cycle > 0) ? ' Återstående GCD visas från början av nästa cykel.' : ''));
  const instantGcd = gcdPreview({...sim.config, castOffset: sim.config.instantOffset, mode: 'parallel'});
  $('instantGcdPreview').replaceChildren(...instantGcd.segments.map(segment => {
    const region = document.createElement('div');
    region.className = 'gcd-region instant-gcd-region';
    region.style.left = (segment.start / sim.config.interval * 100) + '%';
    region.style.width = (segment.duration / sim.config.interval * 100) + '%';
    return region;
  }));
  text('instantPreviewText', 'Orange: planerad Arcane Shot vid ' + format(sim.config.instantOffset * sim.config.interval, 3) +
    ', följd av ' + format(sim.config.gcd) + ' ny GCD. Ingen kasttid.');
  const schedule = schedulePreview(sim.config, $('includeInstant').checked);
  const window = queueWindow(sim.config, $('includeInstant').checked);
  $('queueWindowMarker').hidden = !window.available;
  $('queueWindowMarker').style.left = window.start / sim.config.interval * 100 + '%';
  $('queueWindowMarker').style.width = window.duration / sim.config.interval * 100 + '%';
  text('queueWindowDuration', window.available ? Math.round(window.duration * 1000) + ' ms' : 'Inget fönster');
  text('queueWindowText', window.available ?
    'Turkos markering: ' + format(window.start, 3) + '–' + format(window.end, 3) +
    ' efter Auto Shot (' + number(window.start / sim.config.interval * 100, 1) + '–100 %). ' +
    'Tryck Steady Shot under detta intervall för att köa den till nästa avfyrning. ' +
    'Beräknat för ostörd cykel och förutsätter att planerade spells går iväg; kontrollera konfliktvarningen.' :
    window.reason === 'disabled' ? 'Aktivera köning under uppdragningen i det blockerande läget för att visa Köfönster.' :
    window.reason === 'clipping' ? 'Den planerade casten fördröjer uppdragningen. Justera planen innan ett Köfönster för ostörd cykel kan visas.' :
    'Cast eller GCD blockerar till avfyrningen eller längre. Ingen tid finns att köa under uppdragningen.' +
    (window.overrun > 1e-8 ? ' Spärren slutar ' + format(window.overrun, 3) + ' efter planerad avfyrning.' : ''));
  for (const kind of ['cast', 'instant']) {
    const issue = schedule.issues.find(i => i.kind === kind);
    $(kind === 'cast' ? 'autoMarker' : 'instantMarker').classList.toggle('has-conflict', !!issue);
    $(kind === 'cast' ? 'selectCast' : 'selectInstant').classList.toggle('has-conflict', !!issue);
    $(kind === 'cast' ? 'gcdPreview' : 'instantGcdPreview').classList.toggle('invalid-plan', !!issue);
    $(kind + 'Conflict').replaceChildren(...(issue?.segments ?? []).map(segment => {
      const region = document.createElement('div');
      region.className = 'conflict-region';
      region.style.left = segment.start / sim.config.interval * 100 + '%';
      region.style.width = segment.duration / sim.config.interval * 100 + '%';
      return region;
    }));
  }
  $('scheduleStatus').classList.toggle('has-conflict', !schedule.valid);
  text('scheduleStatus', schedule.valid ? '✓ Inga cast-/GCD-konflikter i den upprepade planen.' :
    '⚠ Planen kan inte utföras varje cykel. ' + schedule.issues.map(issue =>
      (issue.kind === 'cast' ? 'Steady Shot' : 'Arcane Shot') + ' avvisas: ' + issue.reason +
      (issue.carry ? ' från föregående cykel' : '') + ' har ' + format(issue.remaining, 3) +
      ' kvar vid försöket.').join(' ') + ' Flytta knopparna manuellt; inga försök flyttas eller köas om automatiskt.');
  $('castLabel').textContent = 'Cast time ' + format(sim.config.duration);
  text('instantLabel', '10 skada direkt · ' + format(sim.config.gcd) + ' ny GCD' +
    (sim.config.instantCooldown ? ' · ' + format(sim.config.instantCooldown) + ' cooldown' : ''));
  sim.reset(); render();
}
for (const id of ['interval', 'wind', 'gcd', 'duration', 'instantCooldown', 'gcdStart', 'mode', 'queue', 'autoCast', 'castOffset', 'instantOffset', 'includeInstant', 'warmup']) {
  $(id).addEventListener('input', () => {
    if (id === 'castOffset') selectedHandle = 'cast';
    if (id === 'instantOffset') selectedHandle = 'instant';
    settings();
  });
}
function applyPreset(name) {
  for (const [id, value] of Object.entries(PRESETS[name])) $(id).value = value;
  $('mode').value = 'blocking'; $('queue').checked = true;
  settings();
}
$('presetMeasured').onclick = () => applyPreset('measured');
$('presetPrototype').onclick = () => applyPreset('prototype');
function nudge(direction) {
  const range = $(selectedHandle === 'cast' ? 'castOffset' : 'instantOffset');
  // The range also accepts the exact percentage generated by a 10 ms nudge.
  range.step = 'any';
  range.value = Math.max(0, Math.min(100, Number(range.value) + direction * 100 * .01 / sim.config.interval));
  settings();
}
$('earlier').onclick = () => nudge(-1);
$('later').onclick = () => nudge(1);
document.addEventListener('keydown', e => {
  if (e.repeat || e.altKey || e.ctrlKey || e.metaKey || ['INPUT', 'SELECT', 'TEXTAREA', 'BUTTON'].includes(e.target.tagName)) return;
  if (e.code === 'Digit1') { e.preventDefault(); $('cast').click(); }
  if (e.code === 'Digit2') { e.preventDefault(); $('instant').click(); }
  if (e.code === 'Space') { e.preventDefault(); $('play').click(); }
});
let last = performance.now(), nextReadout = 0, fpsStart = last, fpsFrames = 0;
function frame(now) {
  const dt = (now - last) / 1000; last = now;
  if (!document.hidden) {
    fpsFrames++;
    if (now - fpsStart >= 500) {
      text('fps', Math.round(fpsFrames * 1000 / (now - fpsStart)) + ' FPS');
      fpsStart = now; fpsFrames = 0;
    }
    if (sim.running) {
      // Use all elapsed time: slower frames must not silently slow the simulation.
      sim.advance(dt * Number($('speed').value));
      const readouts = now >= nextReadout;
      render(readouts);
      if (readouts) nextReadout = now + 50;
    }
  }
  requestAnimationFrame(frame);
}
document.addEventListener('visibilitychange', () => {
  if (document.hidden && sim.running) {
    sim.running = false; sim.message = 'Pausad när fliken doldes. Fortsätt när du är redo.'; render();
  }
  last = performance.now();
  fpsStart = last; fpsFrames = 0; nextReadout = 0;
});
$('autoCast').checked = true;
$('speed').value = '1';
settings(); requestAnimationFrame(frame);
