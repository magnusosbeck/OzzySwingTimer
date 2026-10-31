import http from 'node:http';
import {readFileSync, mkdtempSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {spawn} from 'node:child_process';
const root = path.resolve('swing-lab/dist');
const server = http.createServer((req,res) => {
  const file = path.resolve(root, '.' + new URL(req.url,'http://localhost').pathname.replace(/\/$/,'/index.html'));
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  try { res.setHeader('Content-Type', ({'.html':'text/html','.css':'text/css','.js':'text/javascript','.mjs':'text/javascript'})[path.extname(file)] ?? 'application/octet-stream');res.end(readFileSync(file)); }
  catch { res.writeHead(404).end(); }
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',[
  '--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking',
  '--remote-debugging-port=0','--user-data-dir='+mkdtempSync(path.join(tmpdir(),'ozzy-browser-')),
  '--window-size=1280,1600','about:blank'],{windowsHide:true,stdio:['ignore','ignore','pipe']});
let ws;
try {
  const endpoint=await new Promise((resolve,reject)=>{let data='';const timer=setTimeout(()=>reject(new Error('Browser startup timed out')),15000);browser.stderr.on('data',chunk=>{data+=chunk;const match=data.match(/DevTools listening on (ws:\/\/[^\s]+)/);if(match){clearTimeout(timer);resolve(match[1]);}});browser.on('error',reject);});
  ws=new WebSocket(endpoint);await new Promise(resolve=>ws.addEventListener('open',resolve));
  let id=0;const pending=new Map(),errors=[];
  ws.addEventListener('message',event=>{const msg=JSON.parse(event.data);if(msg.id){const entry=pending.get(msg.id);pending.delete(msg.id);if(msg.error)entry.reject(new Error(msg.error.message));else entry.resolve(msg.result);}else if(msg.method==='Runtime.exceptionThrown')errors.push(msg.params.exceptionDetails.text+' '+(msg.params.exceptionDetails.exception?.description??''));});
  const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const requestId=++id;pending.set(requestId,{resolve,reject});ws.send(JSON.stringify({id:requestId,method,params,...(sessionId?{sessionId}:{})}));});
  const target=await send('Target.createTarget',{url:'about:blank'});
  const {sessionId}=await send('Target.attachToTarget',{targetId:target.targetId,flatten:true});
  await send('Runtime.enable',{},sessionId);await send('Page.enable',{},sessionId);
  await send('Emulation.setDeviceMetricsOverride',{width:1280,height:1600,deviceScaleFactor:1,mobile:false},sessionId);
  await send('Page.addScriptToEvaluateOnNewDocument',{source:`window.__testNow=0;window.requestAnimationFrame=cb=>(window.__testFrame=cb,1);Object.defineProperty(performance,'now',{value:()=>window.__testNow});window.__advance=ms=>{window.__testNow=ms;window.__testFrame(ms);};`},sessionId);
  await send('Page.navigate',{url:'http://127.0.0.1:'+server.address().port+'/'},sessionId);
  const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},sessionId);if(r.exceptionDetails)throw new Error(r.exceptionDetails.exception?.description??r.exceptionDetails.text);return r.result.value;};
  for(let i=0;i<50;i++){if(await evaluate(`typeof window.__testFrame==='function'`))break;await new Promise(resolve=>setTimeout(resolve,100));}
  const initialDefaults = await evaluate(`({automatic:document.getElementById('autoCast').checked,speed:document.getElementById('speed').value})`);
  if (!initialDefaults.automatic || initialDefaults.speed !== '1') throw new Error('Incorrect initial defaults');
  await evaluate(`document.getElementById('autoCast').checked=false;document.getElementById('speed').value='5';window.__oldPage=true;`);
  await send('Page.reload',{ignoreCache:true},sessionId);
  for(let i=0;i<50;i++){if(await evaluate(`!window.__oldPage && typeof window.__testFrame==='function'`))break;await new Promise(resolve=>setTimeout(resolve,100));}
  const reloadedDefaults = await evaluate(`({automatic:document.getElementById('autoCast').checked,speed:document.getElementById('speed').value})`);
  if (!reloadedDefaults.automatic || reloadedDefaults.speed !== '1') throw new Error('Defaults were not restored on reload');
  console.log(JSON.stringify({initialDefaults,reloadedDefaults}));
  const result=await evaluate(`(()=>{const el=id=>document.getElementById(id),change=(id,value)=>{el(id).value=value;el(id).dispatchEvent(new Event('input',{bubbles:true}));};el('presetPrototype').click();change('speed','1');change('interval','3.1');change('instantOffset','80');el('autoCast').checked=true;el('autoCast').dispatchEvent(new Event('input'));el('play').click();window.__advance(3600);return {phase:el('pendulumPhase').textContent,lock:el('hudLockTime').textContent,segments:[...el('pendulumLocks').children].map(e=>({left:e.style.left,width:e.style.width,background:getComputedStyle(e).backgroundImage,rect:e.getBoundingClientRect().toJSON()}))};})()`);
  console.log(JSON.stringify({result,errors}));
  const bounds=await evaluate(`(()=>{const r=document.querySelector('.hud-preview').getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height,scale:1};})()`);
  const shot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false,clip:bounds},sessionId);
  writeFileSync('.diagnostics/weapon-cooldown-carry.png',Buffer.from(shot.data,'base64'));
  // Prototype values; the page clock is at 3.6 s, so sim time = ms/1000 - 3.6.
  // Shots at 0.5, 3.3, 6.1, 8.9 s; wind-ups 0.5 s before each.
  await evaluate(`(()=>{const el=id=>document.getElementById(id),change=(id,value)=>{el(id).value=value;el(id).dispatchEvent(new Event('input'));};el('presetPrototype').click();el('autoCast').checked=false;el('autoCast').dispatchEvent(new Event('input'));change('interval','2.8');el('play').click();window.__advance(7700);el('cast').click();window.__advance(9400);})()`);
  const fill=()=>evaluate(`getComputedStyle(document.getElementById('pendulumFill')).backgroundColor`);
  const greenColor=await fill();
  if(greenColor!=='rgb(193, 237, 133)')throw new Error('Wind-up should be green when the earlier cast/GCD ends before the shot');
  await evaluate(`document.getElementById('cast').click()`);
  const queuedColor=await fill(), animations=await evaluate(`document.getElementById('pendulumTrack').getAnimations().length`);
  if(queuedColor!==greenColor)throw new Error('Own press during wind-up must keep it green');
  if(animations!==0)throw new Error('No flash on queue');
  await evaluate(`window.__advance(11550);document.getElementById('instant').click();window.__advance(12100)`);
  const redColor=await fill();
  if(redColor!=='rgb(239, 105, 105)')throw new Error('Wind-up should be red when GCD hangs over it');
  const status=await evaluate(`document.getElementById('hudWindupWindowValue').textContent`);
  if(status!=='Ur fas')throw new Error('Status should say out of phase, got '+status);
  // Steady at sim 10.5 s ends 12.0 s, past the 11.2 s wind-up start: the 11.7 s shot slips to 12.5 s (+0,8).
  await evaluate(`window.__advance(14100);document.getElementById('cast').click();window.__advance(16300)`);
  const delayText=await evaluate(`document.getElementById('pendulumDelay').textContent`);
  const delayColor=await evaluate(`getComputedStyle(document.getElementById('pendulumDelay')).color`);
  if(delayText!=='+0,8'||delayColor!=='rgb(239, 105, 105)')throw new Error('Delayed Auto Shot should show red +x,x right of the bar, got '+delayText);
  const windupResult={status,delayText};
  console.log(JSON.stringify({windupResult,greenColor,queuedColor,redColor,animations}));
  const windupShot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false,clip:bounds},sessionId);
  writeFileSync('.diagnostics/windup-window.png',Buffer.from(windupShot.data,'base64'));
  await send('Browser.close');
} finally {ws?.close();browser.kill();server.close();}
