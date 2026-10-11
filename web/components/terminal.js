// Terminal: a Mac terminal window that shows one command and streams its output.
// Terminal({tool, dir, tokens:[html], plain, run:{out,done,code,dry}|null, kind, hint})
// followRun(run, runId, onDone) polls /api/run and appends lines to the open terminal; one loop for every kind of run.
function Terminal(o){const r=o.run;const lines=r?fmtLog(r.out):[];const stages=r?stagesOf(lines,r.done):[];const dir=o.dir?home(o.dir).split('/').pop():'~';
 const status=!r?['','']:!r.done?['running'+(stages.length?' · '+stages[stages.length-1].l.toLowerCase():''),'st-run']:r.dry?['dry run passed','st-done']:r.code===0?['finished','st-done']:['exit '+r.code,'st-bad'];
 const prompt=`<span class=pr>➜</span><span class=pd>${esc(dir)}</span>`;
 return `<div class=console data-kind="${o.kind||'run'}"><div class=ch><span class=tl><i></i><i></i><i></i></span><span class=ttl>${esc(o.tool+' · '+dir+' · zsh')}</span><span class="st ${status[1]}">${r&&!r.done?PulseDot('#8FE3B5',5):''}<span class=st-text>${esc(status[0])}</span>${r&&r.done&&r.rid?` <button class=clr onclick="openLog('${r.rid}')" title="Open the log file. After a failed build, the build log">log</button>`:''}${r&&r.done?` <button class=clr onclick="dismissRun('${o.kind||'run'}')">clear</button>`:''}</span></div>
 <div class=body><div class=cmd>${prompt}<span class=tx>${o.tokens.join(' ')}</span>${r?'':'<span class=caret></span>'}<button class=cp onclick="copyCmd(this,'${esc(o.plain).replace(/'/g,'&#39;')}')" title="Copy the command to run it in your own terminal">copy</button></div>
 <div class=log id=log>${r?lines.map(logLine).join(''):`<span class=e>${o.hint||''}</span>`}${r&&!r.done?'<div class="ln cr"><span class=ts></span><span class=caret></span></div>':''}${r&&r.done?`<div class=ln style="padding-top:6px"><span class=ts></span><span class=prompt>${prompt} <span class=caret></span></span></div>`:''}</div></div></div>`}
const logLine=l=>`<div class="ln${l.head?' head':''}"><span class=ts>${l.head?'':esc(l.ts)}</span><span class="tx ${l.cls}">${esc(l.text).replace(/(https?:\/\/[^\s<>"']+[^\s<>"'.,;:)])/g,m=>`<a class=lf href="${m}" target=_blank rel=noopener>${m}</a>`).replace(/(?<![\w\/="])(\/[^\s:<>"]+\.log)/g,m=>`<a class=lf onclick="openPath('${m}')" title="Open this file">${m}</a>`)}</span></div>`;
function fmtLog(out){const L=[];let ts='';for(const raw of String(out||'').split('\n')){let t=raw.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g,'').replace(/\x1b\(B/g,'');const m0=t.match(/^\[(\d\d:\d\d:\d\d)\] ?/);let stamp='';if(m0){stamp=m0[1];t=t.slice(m0[0].length)}
  if(t.includes('\r'))t=t.split('\r').filter(x=>x.trim()).pop()||'';if(!t.trim())continue;
  if(stamp)ts=stamp;let text=t;
 if(/^\s*[▸◆]/.test(text)){L.push({head:true,text:text.replace(/^\s*[▸◆]\s*/,'').replace(/\s{2,}.*$/,'').trim(),cls:'head',ts});continue}

 // a redraw (a spinner tick, a progress bar, a bare percentage) replaces the redraw before it, as \r would on a terminal
 const tick=/^[▪◦●○·⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏|/\-\\]\s*\d*s?\s/.test(text.trim())||/^(#+\s+)?\d+(\.\d+)?%$/.test(text.trim())||/^[-#=O\s]+$/.test(text.trim());
 if(tick&&L.length&&L[L.length-1].tick){L[L.length-1]=Object.assign(L[L.length-1],{text:text.trim(),ts});continue}
 const s=text.trim();const cls=/^\$/.test(s)?'cmd':/^✓/.test(s)?'ok':/^[⏭→]/.test(s)?'skip':/^[✗!]/.test(s)||/error/i.test(s)?'err':'';L.push({text:s,cls,ts,head:false,tick})}return L}
function stagesOf(lines,done){const order=['Checks','Version','Build','Deploy','Mail','Done'];const map=h=>/dry run · checks|checks/i.test(h)?'Checks':/version/i.test(h)?'Version':/build|files/i.test(h)?'Build':/publish|would run|upload/i.test(h)?'Deploy':/sending|mail/i.test(h)?'Mail':/published|done/i.test(h)?'Done':null;
 const seen=[];lines.filter(l=>l.head).forEach(l=>{const k=map(l.text);if(k&&!seen.includes(k))seen.push(k)});const cur=seen[seen.length-1];return order.filter(k=>seen.includes(k)||(!done&&k===cur)).map(k=>({l:k,k:done||k!==cur?'done':'run'}))}
function streamTerminal(r){const lines=fmtLog(r.out);const log=document.getElementById('log');if(!log)return;
 const rows=log.querySelectorAll('.ln:not(.cr)');const have=rows.length;const caret=log.querySelector('.ln.cr');
 if(have&&lines[have-1]){const last=rows[have-1];const want=logLine(lines[have-1]);if(last.outerHTML!==want)last.outerHTML=want}
 // follow the tail only while the reader is at the tail; a reader who scrolled up stays where they are
 const atTail=log.scrollHeight-log.scrollTop-log.clientHeight<40;
 lines.slice(have).forEach(l=>{const d=document.createElement('div');d.innerHTML=logLine(l);caret?log.insertBefore(d.firstChild,caret):log.appendChild(d.firstChild)});
 if(atTail)log.scrollTop=log.scrollHeight;
 const stages=stagesOf(lines,false);const txt='running'+(stages.length?' · '+stages[stages.length-1].l.toLowerCase():'');const t=document.querySelector('.console .st .st-text');if(t&&t.textContent!==txt)t.textContent=txt}
function followRun(run,rid,onDone){const tick=async()=>{let st;try{st=await (await fetch('/api/run?t='+T+'&id='+rid)).json()}catch(e){st={out:run.out+'\n✗ lost the page server: '+e.message,done:true,code:1}}
  const stamp=new Date().toTimeString().slice(0,8);const prev=run.out.split('\n').length;const lines=String(st.out||'').split('\n');
  run.out=lines.map((l,i)=>i>=prev-1&&l&&!/^\[\d\d:\d\d:\d\d\]/.test(l)?'['+stamp+'] '+l:l).join('\n');
  if(st.done){run.done=true;run.code=st.code;if(window.renderRunning)renderRunning();await onDone(run);return}
  if(window.renderRunning)renderRunning();streamTerminal(run);setTimeout(tick,1000)};tick()}
// startRun(run, url, body, onDone): posts the start, then follows it; any failure lands in the terminal instead of a stuck "running"
async function startRun(run,url,body,onDone){let j;try{const r=await fetch(url+'?t='+T,{method:'POST',body:JSON.stringify(body)});j=r.ok?await r.json():{error:'This page lost its connection to the tool. Close it and open developer-tools ui again.'}}catch(e){j={error:'could not reach the page server: '+e.message}}
 if(j.error){run.out='✗ '+j.error;run.done=true;run.code=1;if(window.renderRunning)renderRunning();render();return}ATTACHED.add(j.run);run.rid=j.run;followRun(run,j.run,onDone)}
// attachRuns(active, make): for each run the server reports still going, build the page's run object and follow it.
// make(meta) returns {slot, run, onDone} or null; called on every data load, so a reloaded page is back on its runs.
const ATTACHED=new Set();
function attachRuns(active,make){(active||[]).forEach(m=>{if(ATTACHED.has(m.run))return;const a=make(m);if(!a)return;ATTACHED.add(m.run);a.run.rid=m.run;ST[a.slot]=a.run;followRun(a.run,m.run,a.onDone)})}
