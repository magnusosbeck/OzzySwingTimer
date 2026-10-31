import assert from 'node:assert/strict';
import {Simulation} from './dist/engine.mjs';
import {castPreview, gcdPreview} from './dist/cast-preview.mjs';
import {schedulePreview} from './dist/schedule-preview.mjs';
import {queueWindow} from './dist/queue-window.mjs';
import {pendulumView} from './dist/pendulum-view.mjs';
import {actionBudget} from './dist/action-budget.mjs';
import {inPhase} from './dist/windup-window.mjs';
const run=c=>{const s=new Simulation(c);s.running=true;return s;};
let s=run();s.advance(6.15);assert.equal(s.shots,3);assert.ok(s.delay<0.016);
s=run();s.pressCast();assert.ok(s.queued);s.advance(.51);assert.equal(s.shots,1);assert.ok(s.castLeft>1.4);assert.equal(s.queued,false);
s=run({duration:3});s.advance(.6);s.pressCast();s.advance(4);assert.equal(s.shots,2);assert.ok(s.delay>0.7);
s=run({mode:'parallel',duration:3});s.advance(.6);s.pressCast();s.advance(3);assert.equal(s.shots,2);assert.ok(s.delay<.016);
s=run();s.toggleMove();s.advance(4);assert.equal(s.shots,0);s.toggleMove();s.advance(.51);assert.equal(s.shots,1);assert.ok(s.delay>3.9);
s=run();s.advance(.6);s.pressCast();s.toggleMove();assert.equal(s.castLeft,0);assert.ok(s.gcdLeft>0);s.running=false;const t=s.t;s.advance(2);assert.equal(s.t,t);s.reset();assert.equal(s.shots,0);assert.equal(s.events.length,0);
console.log('OK: cadence, queue, blocking, parallel casts, movement interruption, pause and reset');

// Equal damage, real cast completions, and DPS denominator.
s=run({autoCast:true,castOffset:0});s.advance(60);
assert.equal(s.shots,22);assert.equal(s.spells,21);assert.equal(s.damage,430);
assert.ok(Math.abs(s.dps-430/60)<1e-8);assert.equal(s.totalDelay,0);
assert.equal(s.autoOnlyDamage,220);assert.ok(s.damage/s.autoOnlyDamage>1.95);
// A late blocking cast clips; a 10 ms shift creates measurable extra delay.
const late=run({autoCast:true,castOffset:1/2.8});late.advance(10);
const later=run({autoCast:true,castOffset:1.01/2.8});later.advance(10);
assert.ok(late.totalDelay>0);assert.ok(later.totalDelay>late.totalDelay+.02);
assert.ok(late.dps<s.dps);
// Queueing within wind-up and exactly at the cycle end preserves Auto Shots.
for(const castOffset of [.9,1]){
  const q=run({autoCast:true,castOffset});q.advance(30);
  assert.equal(q.totalDelay,0);assert.ok(q.spells>8);assert.equal(q.autoMisses,0);
}
// Disabled queue rejects wind-up attempts without inventing damage.
s=run({autoCast:true,castOffset:.9,queue:false});s.advance(12);
assert.equal(s.spells,0);assert.ok(s.autoMisses>0);assert.equal(s.damage,s.shots*10);
// Parallel casts do not clip even at a late start.
s=run({autoCast:true,castOffset:.6,mode:'parallel'});s.advance(12);
assert.equal(s.totalDelay,0);assert.ok(s.spells>0);
// Movement interruptions and paused time must not inflate DPS or damage.
s=run();s.advance(.6);s.pressCast();s.advance(.5);s.toggleMove();s.advance(2);
assert.equal(s.spells,0);assert.equal(s.damage,10);assert.ok(s.clipping>0);
s.running=false;const before=[s.t,s.damage,s.dps,s.clipping];s.advance(30);
assert.deepEqual([s.t,s.damage,s.dps,s.clipping],before);
s.reset();assert.equal(s.damage,0);assert.equal(s.dps,0);assert.equal(s.clipping,0);
// Identical results at different frame rates and playback speeds.
const whole=run({autoCast:true,castOffset:.4}),frames=run({autoCast:true,castOffset:.4});
whole.advance(20);for(let i=0;i<1200;i++)frames.advance(1/60);
assert.deepEqual([whole.shots,whole.spells,whole.totalDelay,whole.t],
  [frames.shots,frames.spells,frames.totalDelay,frames.t]);
console.log('OK: damage/DPS, baseline, 10 ms timing differences, queue endpoints, skipped attempts, clipping and frame independence');

// Playback changes wall-clock duration only, including queueing and clipping cases.
for(const castOffset of [0, .357, .893, 1]) {
  const normal=run({autoCast:true,castOffset}),fast=run({autoCast:true,castOffset});
  for(let frame=0;frame<3600;frame++)normal.advance(1/60);
  for(let frame=0;frame<720;frame++)fast.advance(5/60);
  const result=s=>[s.t,s.shots,s.spells,s.damage,s.dps,s.clipping,s.autoMisses];
  assert.deepEqual(result(normal),result(fast));
}
console.log('OK: 1x and 5x produce identical damage, DPS, clipping and shot counts at equal simulated time');

// Displayed DPS is sampled exactly at complete shot-to-shot cycle boundaries.
s=run({autoCast:true});s.advance(.5);assert.equal(s.dpsSample,null);
s.advance(2.8);assert.ok(s.dpsSample);assert.ok(Math.abs(s.dpsSample.time-3.3)<1e-8);
assert.equal(s.dpsSample.dps,s.dps);const sampled=s.dpsSample;
s.advance(1.6);assert.equal(s.spells,2);assert.equal(s.dpsSample,sampled);
assert.notEqual(s.dps,sampled.dps);s.advance(1.2);
assert.notEqual(s.dpsSample,sampled);assert.equal(s.dpsSample.dps,s.dps);
const exact=run({autoCast:true});exact.advance(6.11);
assert.ok(Math.abs(exact.dpsSample.time-6.1)<1e-8);
assert.ok(Math.abs(exact.dpsSample.dps-50/6.1)<1e-8);
exact.reset();assert.equal(exact.dpsSample,null);
console.log('OK: DPS display holds between complete cycles, samples exact boundaries and clears on reset');

// Per-cycle margin: spare time, exact fit, clipping, and no accumulated penalty.
for(const [offset,expectedMargin] of [[0,.8],[.8/2.8,0],[1/2.8,-.2],[.893,.8]]) {
  const q=run({autoCast:true,castOffset:offset});q.advance(10);
  assert.ok(Math.abs(q.dpsSample.margin-expectedMargin)<.0011);
  const snapshot=q.dpsSample;q.advance(.1);assert.equal(q.dpsSample,snapshot);
}
const recovery=run({autoCast:true,castOffset:1/2.8});recovery.advance(3.5);
assert.ok(recovery.dpsSample.margin<0);recovery.config.castOffset=0;
recovery.advance(2.8);assert.ok(Math.abs(recovery.dpsSample.margin-.8)<.0011);
assert.ok(recovery.totalDelay>0); // past clipping does not color a later safe cycle red.
const noCast=run();noCast.advance(3.3);assert.equal(noCast.dpsSample.margin,0);
const parallel=run({autoCast:true,mode:'parallel',castOffset:.6});parallel.advance(10);
assert.equal(parallel.dpsSample.margin,0);
console.log('OK: cycle margin is positive for spare time, zero for exact fit, negative for clipping and recovers next cycle');

// Warm-up excludes both initial time and damage, then samples entire cycles.
for(const castOffset of [0,.25,.8/2.8,.893,1]) {
  const q=run({autoCast:true,castOffset,warmup:true});
  while(q.shots<9)q.advance(.001);
  assert.equal(q.measurementStart,null);assert.equal(q.dpsSample.dps,null);
  while(q.shots<10)q.advance(.001);
  assert.ok(q.measurementStart);assert.equal(q.dpsSample.dps,null);
  assert.equal(q.measurementStart.damage,q.damage);
  while(q.shots<20)q.advance(.001);
  assert.ok(Math.abs(q.dpsSample.dps-20/2.8)<1e-8);
  assert.ok(Math.abs(q.dpsSample.elapsed-28)<1e-8);
  assert.ok(Math.abs(q.dpsSample.ratio-2)<1e-8);
  const sampled=q.dpsSample;q.advance(.1);assert.equal(q.dpsSample,sampled);
  q.reset();assert.equal(q.measurementStart,null);assert.equal(q.dpsSample,null);
}
const clippedWarm=run({autoCast:true,castOffset:1/2.8,warmup:true});
while(clippedWarm.shots<20)clippedWarm.advance(.001);
assert.ok(Math.abs(clippedWarm.dpsSample.dps-20/3)<1e-8);
assert.ok(Math.abs(clippedWarm.dpsSample.elapsed-30)<1e-8);
assert.ok(clippedWarm.dpsSample.margin<0);
console.log('OK: warm-up removes start bias across early/queued timing, preserves clipping cost and resets correctly');

const previewConfig={interval:2.8,wind:.5,duration:1.5,gcd:1.5,castOffset:0,mode:'blocking',queue:true};
let preview=castPreview(previewConfig);
assert.deepEqual(preview.segments,[{cycle:0,start:0,duration:1.5}]);
preview=castPreview({...previewConfig,castOffset:.893});
assert.equal(preview.queued,true);assert.ok(Math.abs(preview.visible-1.5)<1e-8);
assert.equal(preview.segments[0].cycle,1);assert.equal(preview.segments[0].start,0);
preview=castPreview({...previewConfig,castOffset:1/2.8});
assert.ok(Math.abs(preview.visible-1.3)<1e-8);assert.ok(Math.abs(preview.overflow-.2)<1e-8);
preview=castPreview({...previewConfig,castOffset:.893,queue:false});
assert.equal(preview.rejected,true);assert.equal(preview.segments.length,0);
preview=castPreview({...previewConfig,castOffset:2.6/2.8,mode:'parallel'});
assert.ok(Math.abs(preview.visible-1.3)<1e-8);assert.equal(preview.segments[0].cycle,1);
for(const castOffset of [0,.2,.5,.82,.9,1])for(const mode of ['blocking','parallel']){
  const p=castPreview({...previewConfig,castOffset,mode});
  for(const segment of p.segments){assert.ok(segment.start>=0);assert.ok(segment.start+segment.duration<=2.3+1e-8);}
}
console.log('OK: cast preview clips to cooldown, queues the full duration, flags overflow and subtracts only actual parallel overlap');

let gcd=gcdPreview(previewConfig);
assert.deepEqual(gcd.segments,[{cycle:0,start:0,duration:1.5}]);
gcd=gcdPreview({...previewConfig,castOffset:.893});
assert.equal(gcd.queued,true);assert.deepEqual(gcd.segments,[{cycle:1,start:0,duration:1.5}]);
gcd=gcdPreview({...previewConfig,castOffset:1.8/2.8,duration:.5});
assert.equal(gcd.segments.length,2);
assert.ok(Math.abs(gcd.segments.reduce((sum,s)=>sum+s.duration,0)-1.5)<1e-8);
assert.ok(gcd.segments[0].start+gcd.segments[0].duration>2.3); // GCD may span wind-up.
assert.equal(gcd.segments[1].start,0);
assert.deepEqual(gcdPreview({...previewConfig,duration:.5}).segments,
  gcdPreview({...previewConfig,duration:3}).segments);
assert.equal(gcdPreview({...previewConfig,castOffset:.9,queue:false}).segments.length,0);
console.log('OK: GCD preview uses cast start, keeps 1.5 s independent of cast duration, wraps across cycles and respects queue rejection');

// GCD may finish before or after the actual cast; both gate the next spell.
s=run({gcd:1,duration:1.5});s.advance(.5);s.pressCast();s.advance(1.01);
assert.equal(s.gcdLeft,0);assert.ok(s.castLeft>.48);assert.equal(s.pressCast(),false);
s.advance(.49);assert.equal(s.castLeft,0);assert.equal(s.pressCast(),true);
s=run({gcd:1.5,duration:.5});s.advance(.5);s.pressCast();s.advance(.6);
assert.equal(s.castLeft,0);assert.ok(s.gcdLeft>.89);assert.equal(s.pressCast(),false);
const longGcd=run({gcd:2,duration:.5,interval:1.5,wind:.5,autoCast:true});longGcd.advance(2);
assert.equal(longGcd.shots,2);assert.ok(longGcd.gcdLeft>0);assert.equal(longGcd.delay,0);
assert.deepEqual(gcdPreview({...previewConfig,gcd:1}).segments,[{cycle:0,start:0,duration:1}]);
assert.equal(gcdPreview({...previewConfig,gcd:1}).duration,1);
console.log('OK: configurable GCD is independent of cast duration and does not block Auto Shot by itself');

// InstaCast: immediate damage, no cast time, a fresh shared GCD, no Auto Shot reset.
s=run();assert.equal(s.pressInstant(),true);assert.equal(s.instants,1);
assert.equal(s.damage,10);assert.equal(s.castLeft,0);assert.equal(s.gcdLeft,1);
assert.equal(s.gcdSource,'instant');assert.equal(s.pressInstant(),false);
s.advance(.5);assert.equal(s.shots,1);assert.equal(s.delay,0);
s.advance(.5);assert.equal(s.pressInstant(),true);assert.equal(s.gcdLeft,1);
// Cannot bypass a cast or a queued spell even if GCD is already ready.
s=run();s.advance(.5);s.pressCast();s.advance(1.01);assert.equal(s.gcdLeft,0);
assert.equal(s.pressInstant(),false);s.advance(.49);assert.equal(s.pressInstant(),true);
assert.equal(s.spells,1);assert.equal(s.instants,1);assert.equal(s.damage,30);
// Both automatic offsets repeat independently, respecting warm-up and shared GCD.
for(const castOffset of [0,.97]) {
  const q=run({autoCast:true,autoInstant:true,castOffset,instantOffset:.6,warmup:true});
  while(q.shots<20)q.advance(.001);
  assert.ok(Math.abs(q.dpsSample.dps-30/2.8)<1e-8);
  assert.equal(q.delay,0);assert.equal(q.autoMisses,0);assert.ok(q.instants>0);
}
const tooEarly=run({autoCast:true,autoInstant:true,instantOffset:.4});tooEarly.advance(12);
assert.equal(tooEarly.instants,0);assert.ok(tooEarly.instantMisses>0);
const blockedQueue=run({autoCast:true,autoInstant:true,castOffset:.893,instantOffset:.6});blockedQueue.advance(12);
assert.ok(blockedQueue.autoMisses>0);assert.equal(blockedQueue.spells,0);
const lateInstant=run({autoCast:true,autoInstant:true,instantOffset:.9});lateInstant.advance(3.31);
assert.equal(lateInstant.shots,2);assert.equal(lateInstant.instants,1);
assert.equal(lateInstant.spells,1);assert.ok(lateInstant.autoMisses>0);assert.equal(lateInstant.delay,0);
const tied=run({autoCast:true,autoInstant:true,instantOffset:0});tied.advance(.51);
assert.ok(tied.castLeft>0);assert.equal(tied.instants,0);assert.equal(tied.instantMisses,1);
// 100% offset attempts fire once per cycle, before the release snapshot.
const endpoint=run({autoInstant:true,instantOffset:1});endpoint.advance(6.1);
assert.equal(endpoint.instants,2);assert.equal(endpoint.shots,3);
// Playback speed must not alter a two-spell schedule.
const a=run({autoCast:true,autoInstant:true}),b=run({autoCast:true,autoInstant:true});
for(let frame=0;frame<3600;frame++)a.advance(1/60);
for(let frame=0;frame<720;frame++)b.advance(5/60);
assert.deepEqual([a.shots,a.spells,a.instants,a.damage,a.autoMisses],
  [b.shots,b.spells,b.instants,b.damage,b.autoMisses]);
b.reset();assert.equal(b.instants,0);assert.equal(b.instantMisses,0);
console.log('OK: InstaCast damage, new GCD, busy rejection, two automatic handles, warm-up DPS, endpoints and playback invariance');

const plan={interval:2.8,wind:.5,duration:.5,gcd:1,mode:'blocking',queue:true,castOffset:0,instantOffset:.76};
const carryPlan=schedulePreview(plan,true);
assert.equal(carryPlan.valid,false);
const carryIssue=carryPlan.issues.find(i=>i.kind==='cast');
assert.equal(carryIssue.reason,'GCD');assert.equal(carryIssue.carry,true);
assert.ok(Math.abs(carryIssue.remaining-.328)<.0011);
assert.equal(schedulePreview({...plan,instantOffset:.6},true).valid,true);
assert.equal(schedulePreview(plan,false).valid,true);
const duringCast=schedulePreview({...plan,duration:1.5,instantOffset:.4},true);
assert.equal(duringCast.issues.find(i=>i.kind==='instant').reason,'en pågående cast');
assert.equal(duringCast.issues.find(i=>i.kind==='instant').carry,false);
const ownGcd=schedulePreview({...plan,instantOffset:.25},true).issues.find(i=>i.kind==='instant');
assert.equal(ownGcd.reason,'GCD');assert.equal(ownGcd.carry,false);
assert.equal(schedulePreview({...plan,instantOffset:1/2.8},true).valid,true); // exact GCD boundary
assert.equal(plan.instantOffset,.76);assert.equal(plan.castOffset,0); // no automatic knob movement
for(const issue of carryPlan.issues)for(const segment of issue.segments){
  assert.ok(segment.start>=0);assert.ok(segment.start+segment.duration<=plan.interval+1e-8);
}
console.log('OK: conflict preview catches 0.328 s carry, distinguishes cast/GCD blockers, accepts exact boundaries and never moves offsets');

const queuePlan={interval:2.8,wind:.5,duration:1.5,gcd:1,castOffset:0,instantOffset:1.5/2.8,mode:'blocking',queue:true};
let window=queueWindow(queuePlan,true);
assert.equal(window.available,true);assert.ok(Math.abs(window.start-2.5)<1e-8);
assert.ok(Math.abs(window.duration-.3)<1e-8);assert.equal(window.end,2.8);
assert.ok(Math.abs(queueWindow(queuePlan,false).duration-.5)<1e-8);
assert.ok(Math.abs(queueWindow({...queuePlan,castOffset:.97},true).duration-.3)<1e-8);
assert.ok(Math.abs(queueWindow({...queuePlan,instantOffset:.6},true).duration-.12)<1e-8);
window=queueWindow({...queuePlan,instantOffset:.76},true);
assert.equal(window.available,false);assert.ok(Math.abs(window.overrun-.328)<1e-8);
assert.equal(queueWindow({...queuePlan,queue:false},true).reason,'disabled');
assert.equal(queueWindow({...queuePlan,mode:'parallel'},true).reason,'disabled');
assert.equal(queueWindow({...queuePlan,duration:2.5},true).reason,'clipping');
assert.equal(queueWindow({...queuePlan,instantOffset:1.8/2.8},true).available,false);
console.log('OK: queue window spans 300 ms, respects wind-up/cast/GCD, handles queued casts and disables invalid cases');

// Pendulum keeps its moving edge continuous at the turn and release boundaries.
const viewState={config:{interval:2.8,wind:.5},castLeft:0};
const slowStart=pendulumView({...viewState,phase:'cooldown',progress:0});
const slowEnd=pendulumView({...viewState,phase:'cooldown',progress:2.3});
const fastStart=pendulumView({...viewState,phase:'wind',progress:0});
const fastEnd=pendulumView({...viewState,phase:'wind',progress:.5});
assert.equal(slowStart.cursor,1);assert.equal(slowStart.fill,0);
assert.equal(slowEnd.cursor,fastStart.cursor);assert.equal(slowEnd.cursor,0);
assert.equal(fastEnd.cursor,slowStart.cursor);assert.equal(fastEnd.cursor,1);
assert.equal(slowStart.origin,'right center');assert.equal(fastStart.origin,'left center');
assert.ok(Math.abs(pendulumView({...viewState,phase:'cooldown',progress:1.15}).cursor-.5)<1e-8);
assert.equal(pendulumView({...viewState,phase:'wind',progress:.25}).cursor,.5);
const blockedView=pendulumView({...viewState,phase:'blocked',progress:0,castLeft:.2});
assert.equal(blockedView.cursor,0);assert.equal(blockedView.remaining,.2);
assert.equal(pendulumView({...viewState,phase:'wind',progress:.9}).cursor,1);
console.log('OK: pendulum directions, phase durations, continuous endpoints, blocked state and clamped positions');

// Actual late cast placement and max(cast,GCD), not their sum.
s=run({interval:3.1});s.advance(.5);s.pressCast();s.advance(.1);
let budget=actionBudget(s);
assert.ok(Math.abs(budget.busy-1.4)<1e-8);assert.ok(Math.abs(budget.free-1.1)<1e-8);
assert.equal(budget.fitsCast,false);assert.equal(budget.fitsInstant,true);
assert.ok(Math.abs(budget.segments[0].width-1.5/2.6)<1e-8);
s.advance(1.4);s.pressInstant();budget=actionBudget(s);
assert.ok(Math.abs(budget.free-.1)<1e-8);assert.equal(budget.segments.length,2);
assert.equal(budget.fitsInstant,false);
const lateCast=run();lateCast.advance(1);lateCast.pressCast();budget=actionBudget(lateCast);
assert.ok(Math.abs(budget.segments[0].left-(1-2/2.3))<1e-8);
assert.ok(Math.abs(budget.segments[0].duration-1.5)<1e-8);
const longLock=run({interval:1.5,duration:.5,gcd:2});longLock.advance(.5);longLock.pressCast();
assert.ok(Math.abs(longLock.actionLocks[0].end-longLock.actionLocks[0].start-2)<1e-8);
longLock.advance(1.5);budget=actionBudget(longLock);
assert.equal(longLock.shots,2);assert.ok(budget.busy>0);assert.ok(budget.segments.length);
const queuedLock=run();queuedLock.pressCast();assert.equal(queuedLock.actionLocks.length,0);
queuedLock.advance(.5);assert.equal(queuedLock.actionLocks.length,1);
assert.ok(Math.abs(queuedLock.actionLocks[0].start-.5)<1e-8);
const interrupted=run({duration:3});interrupted.advance(.5);interrupted.pressCast();
interrupted.advance(.2);interrupted.toggleMove();
assert.ok(Math.abs(interrupted.actionLocks[0].end-1.5)<1e-8);
queuedLock.reset();assert.equal(queuedLock.actionLocks.length,0);
console.log('OK: Action lock uses actual start/max duration, mirrors late casts, includes instant GCD/carry, waits for queued start and resets');

const windupState={phase:'wind',config:{wind:.5,mode:'blocking',queue:true},t:2.4,progress:.1,
  actionLocks:[{start:1.5,end:2.5}],running:true,queued:false,moving:false,castLeft:0,gcdLeft:.1};
assert.equal(inPhase(windupState),true);
assert.equal(inPhase({...windupState,actionLocks:[{start:1.5,end:2.9}]}),false);
assert.equal(inPhase({...windupState,actionLocks:[{start:1.5,end:2.5},{start:2.35,end:3.85}]}),true);
assert.equal(inPhase({...windupState,phase:'cooldown'}),null);
assert.equal(pendulumView(windupState).color,'#c1ed85');
assert.equal(pendulumView({...windupState,actionLocks:[{start:1.5,end:2.9}]}).color,'#ef6969');
assert.equal(pendulumView({...windupState,phase:'cooldown'}).color,'#c1ed85');
console.log('OK: wind-up green when earlier actions end by the shot, red when GCD hangs over it; own press keeps it green');

s=run();assert.equal(s.queueAcceptCount,0);s.pressCast();assert.equal(s.queueAcceptCount,1);
s.pressCast();assert.equal(s.queueAcceptCount,1);s.advance(.5);
assert.equal(s.queueAcceptCount,1);assert.equal(s.queued,false);
const ordinary=run();ordinary.advance(.5);ordinary.pressCast();assert.equal(ordinary.queueAcceptCount,0);
const rejected=run({queue:false});rejected.pressCast();assert.equal(rejected.queueAcceptCount,0);
const locked=run();locked.pressInstant();locked.pressCast();assert.equal(locked.queueAcceptCount,0);
const automatic=run({autoCast:true,castOffset:.97});automatic.advance(3.31);
assert.equal(automatic.queueAcceptCount,1);assert.equal(automatic.queued,false);
automatic.reset();assert.equal(automatic.queueAcceptCount,0);
console.log('OK: flash event fires once per accepted queue, never on cooldown/rejection and survives release before rendering');

// Measured in TBC 2.5.6: a cast queued in wind-up starts at release, but its GCD starts at the press.
const measured={interval:2.29,wind:.36,gcd:1.5,duration:1.15};
for(const [gcdStart,left] of [['press',1.34],['cast',1.5]]){
  const g=run({...measured,gcdStart});g.advance(.2);assert.ok(g.pressCast());assert.ok(g.queued);
  assert.ok(Math.abs(g.gcdLeft-(gcdStart==='press'?1.5:0))<1e-6);
  g.advance(.161);assert.equal(g.shots,1);assert.ok(Math.abs(g.castLeft-1.15)<.002);
  assert.ok(Math.abs(g.gcdLeft-left)<.002,gcdStart+' gcdLeft '+g.gcdLeft);
  assert.ok(Math.abs(g.actionLocks.at(-1).end-g.t-Math.max(1.15,left))<.002);
}
const pressGcd=gcdPreview({...measured,castOffset:.95,mode:'blocking',queue:true,gcdStart:'press'});
assert.ok(pressGcd.queued);assert.equal(pressGcd.segments[0].cycle,0);
assert.ok(Math.abs(pressGcd.segments[0].start-.95*2.29)<1e-6);
const castGcd=gcdPreview({...measured,castOffset:.95,mode:'blocking',queue:true,gcdStart:'cast'});
assert.equal(castGcd.segments[0].cycle,1);assert.equal(castGcd.segments[0].start,0);
const pressWindow=queueWindow({...measured,gcd:2,castOffset:.95,mode:'blocking',queue:true,gcdStart:'press'},false);
const castWindow=queueWindow({...measured,gcd:2,castOffset:.95,mode:'blocking',queue:true,gcdStart:'cast'},false);
assert.ok(Math.abs(pressWindow.duration-.36)<1e-6);assert.ok(Math.abs(castWindow.duration-.29)<1e-6);
console.log('OK: GCD from press runs during wind-up, cast still starts at release; previews follow the setting');

// Steady Shot + instant per cycle with measured values: 2 × 1.5 s GCD cannot fit in 2.29 s.
const measuredPair={interval:2.29,wind:.36,gcd:1.5,duration:1.11,gcdStart:'press',mode:'blocking',queue:true};
assert.ok(schedulePreview({...measuredPair,castOffset:.95,instantOffset:.62},false).valid);
assert.equal(schedulePreview({...measuredPair,castOffset:.95,instantOffset:.62},true).valid,false);
console.log('OK: Steady Shot alone fits every cycle; Steady + instant conflicts via GCD with measured values');

// Delay after an instant is "worth it" below break-even; a cast alone is not (prototype values).
const worth=run({gcdStart:'cast'});worth.advance(1);assert.ok(worth.pressInstant());worth.advance(1);
assert.ok(worth.pressCast());worth.advance(2.1);assert.ok(Math.abs(worth.delay-.7)<.002);assert.equal(worth.delayWorthIt,true);
const alone=run({gcdStart:'cast'});alone.advance(2);assert.ok(alone.pressCast());alone.advance(2.1);
assert.ok(Math.abs(alone.delay-.7)<.002);assert.equal(alone.delayWorthIt,false);
const strict=run({gcdStart:'cast',breakEven:.5});strict.advance(1);strict.pressInstant();strict.advance(1);strict.pressCast();strict.advance(2.1);
assert.equal(strict.delayWorthIt,false);
console.log('OK: delay after an instant is yellow below break-even, red alone or above it');
