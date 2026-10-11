// AppGrid — the grouped-corner language in 2D, from DevSwitch's AppGrid.kt: only the grid's four outer
// corners round to 16px, every inner corner stays 4px, 4px seams. A short last row stretches to fill.
// AppGrid({title, columns, layout:'Stacked'|'Leading', items:[{title, subtitle, icon, selected, enabled, onclick}], after})
// A cell with no onclick is a read-only stat cell. `after` is extra HTML drawn under the grid, inside the group (a field, say).
function AppGrid(o){
 const items=(o.items||[]).filter(Boolean);if(!items.length)return'';
 const cols=Math.max(1,o.columns||2),layout=(o.layout||'Stacked').toLowerCase();
 const rows=[];for(let i=0;i<items.length;i+=cols)rows.push(items.slice(i,i+cols));
 const last=rows.length-1;
 const cell=(it,r,c,n)=>{const click=it.enabled!==false&&it.onclick;
  const corners=[r===0&&c===0,r===0&&c===n-1,r===last&&c===n-1,r===last&&c===0].map(b=>b&&!o.after?'16px':b&&r!==last?'16px':'4px').join(' ');
  const cls=['gcell','g-'+layout,it.selected?'sel':'',it.enabled===false?'off':'',click?'click':''].filter(Boolean).join(' ');
  return `<div class="${cls}" style="border-radius:${corners}"${click?` onclick="${it.onclick}" role=button tabindex=0 onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();this.click()}"`:''}${it.icon?Icon(it.icon,layout==='stacked'?22:20):''}<span class=gtx>${layout==='leading'&&it.subtitle?`<span class=gsub>${it.subtitle}</span>`:''}<span class=gtitle>${it.title}</span>${layout==='stacked'&&it.subtitle?`<span class=gsub>${it.subtitle}</span>`:''}</span></div>`};
 return `<div class=grid${o.id?` id=${o.id}`:''}>${o.title?`<span class=gh>${o.title}</span>`:''}${rows.map((row,r)=>`<div class=grow>${row.map((it,c)=>cell(it,r,c,row.length)).join('')}</div>`).join('')}${o.after?`<div class=gafter>${o.after}</div>`:''}</div>`}
