// AppTile — a borderless filled row. The group owns the corners: First 16/4, Middle 4, Last 4/16, Single 16.
// AppTile({title, subtitle, variant:'Normal|Success|Warning|Error', position, leadingIcon, leadingColor, trailing, actions:[{icon,onclick,title,busy}], selected, enabled, onclick, id, attrs})
function AppTile(o){
 const pos=(o.position||'Single').toLowerCase(),v=(o.variant||'Normal').toLowerCase();
 const click=o.enabled!==false&&o.onclick;
 const cls=['tile','tile-'+pos,'tile-'+v,o.selected?'sel':'',o.enabled===false?'off':'',click?'click':''].filter(Boolean).join(' ');
 const lead=o.leadingIcon?`<span class=tile-halo${o.leadingColor?` style="--halo:${o.leadingColor}"`:''}>${Icon(o.leadingIcon,20)}</span>`:'';
 const acts=(o.actions||[]).map(a=>`<span class="tile-act${a.busy?' busy':''}" title="${a.title||''}" onclick="event.stopPropagation();${a.busy?'':a.onclick}">${a.busy&&a.icon!=='refresh-cw'?'<span class=spin></span>':Icon(a.icon,18)}</span>`).join('');
 const trail=o.trailing?`<span class=tile-trail>${o.trailing}</span>`:acts?`<span class=tile-acts>${acts}</span>`:click?`<span class=tile-trail>${Icon('chevron-right',20)}</span>`:'';
 return `<div class="${cls}"${o.id?` id=${o.id}`:''}${click?` onclick="${o.onclick}" role=button tabindex=0 onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();this.click()}"`:''} ${o.attrs||''}>${lead}<span class=tile-body><span class=tile-title>${o.title}</span>${o.subtitle?`<span class=tile-sub>${o.subtitle}</span>`:''}</span>${trail}</div>`}

// AppTileGroup — a titled stack of tiles with 4px gaps; positions are assigned here.
// AppTileGroup({title, aside, items:[tileOpts], variant, empty, collapsible:{key, title, subtitle, leadingIcon, aside, force}})
// collapsible: the header is the first tile; the stack folds under it. The fold, the chevron turn and the
// open state live here, like animateContentSize in the Kotlin AppTile, so no caller animates anything.
const TG_CLOSED=new Set();
window.tgToggle=(el,key)=>{const open=TG_CLOSED.has(key);open?TG_CLOSED.delete(key):TG_CLOSED.add(key);
 el.classList.toggle('open',open);el.classList.toggle('tile-first',open);el.classList.toggle('tile-single',!open);el.closest('.tg').querySelector('.fold').classList.toggle('closed',!open)};
function AppTileGroup(o){
 const items=(o.items||[]).filter(Boolean);if(!items.length&&!o.empty)return'';
 const c=o.collapsible,n=items.length;
 const pos=i=>c?(i===n-1?'Last':'Middle'):n===1?'Single':i===0?'First':i===n-1?'Last':'Middle';
 const tiles=items.map((t,i)=>AppTile(Object.assign({position:pos(i),variant:o.variant},t))).join('');
 if(c){const open=!TG_CLOSED.has(c.key)||!!c.force;
  const head=AppTile({position:open?'First':'Single',leadingIcon:c.leadingIcon,title:c.title,subtitle:c.subtitle,selected:!open&&items.some(t=>t.selected),trailing:(c.aside?Meta(c.aside):'')+Icon('chevron-down',20,'class="ico chev"'),onclick:`tgToggle(this,'${c.key}')`}).replace('class="tile ','class="tile '+(open?'open ':''));
  return `<div class=tg${o.id?` id=${o.id}`:''}>${head}<div class="fold${open?'':' closed'}"><div>${tiles}</div></div></div>`}
 const head=o.title?`<div class=tg-head><span class="tg-title tg-${(o.variant||'Normal').toLowerCase()}">${o.title}</span>${o.aside?`<span class=tg-aside>${o.aside}</span>`:''}</div>`:'';
 return `<div class=tg${o.id?` id=${o.id}`:''}>${head}<div class=tg-list>${tiles||o.empty||''}</div></div>`}

// Meta — the small trailing text a tile shows instead of a chevron
const Meta=(t,c)=>`<span class=tile-meta${c?` style="color:${c}"`:''}>${t}</span>`;
