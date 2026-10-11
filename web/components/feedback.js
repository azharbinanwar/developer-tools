// AppNotice — one line of attention: halo icon, title, message, optional action, optional dismiss.
// AppNotice({title, message, icon, variant:'Normal|Success|Warning|Error', actionLabel, onAction, dismiss})
function AppNotice(o){
 const v=(o.variant||'Normal').toLowerCase();
 return `<div class="notice notice-${v}">${o.icon?`<span class=notice-ico>${Icon(o.icon,19)}</span>`:''}<span class=notice-body><span class=notice-title>${o.title}</span>${o.message?`<span class=notice-msg>${o.message}</span>`:''}</span>${o.actionLabel&&o.onAction?AppButton({text:o.actionLabel,variant:'Text',size:'Small',onclick:o.onAction}):''}${o.dismiss?`<span class=notice-x onclick="${o.dismiss}">${Icon('x',18)}</span>`:''}</div>`}

// StateView — an empty or error state, centred.
function StateView(o){return `<div class=state>${o.icon?`<span class=state-ico>${Icon(o.icon,40)}</span>`:''}<span class=state-title>${o.title}</span>${o.message?`<span class=state-msg>${o.message}</span>`:''}${o.action?`<span class=state-act>${o.action}</span>`:''}</div>`}

// PulseDot — the only looping animation.
const PulseDot=(color='var(--primary)',size=9)=>`<span class=pulse style="--c:${color};--s:${size}px"><span class=ring></span><span class=dot></span></span>`;

// Toast — a notice that slides in top right, like the admin's notify. Stays 7 s, or until clicked.
// toast({title, message, variant:'Normal|Success|Warning|Error', icon, actionLabel, onAction})
window.toast=o=>{let box=document.getElementById('toasts');if(!box){box=document.createElement('div');box.id='toasts';document.body.appendChild(box)}
 const el=document.createElement('div');el.className='toast';el.innerHTML=AppNotice(Object.assign({dismiss:'this.closest(\'.toast\').remove()'},o));
 el.addEventListener('click',e=>{if(!e.target.closest('button'))el.remove()});box.appendChild(el);requestAnimationFrame(()=>el.classList.add('in'));
 setTimeout(()=>{el.classList.remove('in');setTimeout(()=>el.remove(),260)},o.stay||7000);return el};
