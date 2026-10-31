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
  const result=await evaluate(`(()=>{const el=id=>document.getElementById(id),change=(id,value)=>{el(id).value=value;el(id).dispatchEvent(new Event('input',{bubbles:true}));};change('speed','1');change('interval','3.1');change('instantOffset','80');el('autoCast').checked=true;el('autoCast').dispatchEvent(new Event('input'));el('play').click();window.__advance(3600);return {phase:el('pendulumPhase').textContent,lock:el('hudLockTime').textContent,segments:[...el('pendulumLocks').children].map(e=>({left:e.style.left,width:e.style.width,background:getComputedStyle(e).backgroundImage,rect:e.getBoundingClientRect().toJSON()}))};})()`);
  console.log(JSON.stringify({result,errors}));
  const bounds=await evaluate(`(()=>{const r=document.querySelector('.hud-preview').getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height,scale:1};})()`);
  const shot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false,clip:bounds},sessionId);
  writeFileSync('.diagnostics/weapon-cooldown-carry.png',Buffer.from(shot.data,'base64'));
  const windupResult=await evaluate(`(()=>{const el=id=>document.getElementById(id),change=(id,value)=>{el(id).value=value;el(id).dispatchEvent(new Event('input'));};el('autoCast').checked=false;el('autoCast').dispatchEvent(new Event('input'));change('interval','2.8');el('play').click();window.__advance(4100);el('cast').click();window.__advance(5600);el('instant').click();window.__advance(6500);const zone=el('hudWindupWindow');return {value:el('hudWindupWindowValue').textContent,left:zone.style.left,width:zone.style.width,hidden:zone.hidden,phase:el('pendulumPhase').textContent};})()`);
  if(windupResult.hidden || Math.abs(parseFloat(windupResult.left)-40)>0.001 || Math.abs(parseFloat(windupResult.width)-60)>0.001)throw new Error('Incorrect wind-up zone geometry');
  const redColor=await evaluate(`getComputedStyle(document.getElementById('pendulumFill')).backgroundColor`);
  if(redColor!=='rgb(239, 105, 105)')throw new Error('Wind-up should be red before queue window');
  await evaluate(`document.getElementById('cast').click()`);
  const rejectedFlash=await evaluate(`document.getElementById('pendulumTrack').getAnimations().length`);
  if(rejectedFlash!==0)throw new Error('Rejected cast must not flash');
  await evaluate(`window.__advance(6600)`);
  const greenColor=await evaluate(`getComputedStyle(document.getElementById('pendulumFill')).backgroundColor`);
  if(greenColor!=='rgb(193, 237, 133)')throw new Error('Wind-up should be green inside queue window');
  await evaluate(`document.getElementById('cast').click()`);
  const flash=await evaluate(`(()=>{const a=document.getElementById('pendulumTrack').getAnimations();return {count:a.length,duration:a[0]?.effect.getTiming().duration,outline:a[0]?.effect.getKeyframes()[0].outlineWidth};})()`);
  if(flash.count!==1 || flash.duration!==350 || flash.outline!=='4px')throw new Error('Accepted queue must flash thick outline once');
  const queuedColor=await evaluate(`getComputedStyle(document.getElementById('pendulumFill')).backgroundColor`);
  if(queuedColor!==greenColor)throw new Error('Wind-up must remain green after queueing inside window');
  console.log(JSON.stringify({windupResult,redColor,greenColor,queuedColor,rejectedFlash,flash}));
  const windupShot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false,clip:bounds},sessionId);
  writeFileSync('.diagnostics/windup-window.png',Buffer.from(windupShot.data,'base64'));
  await send('Browser.close');
} finally {ws?.close();browser.kill();server.close();}
