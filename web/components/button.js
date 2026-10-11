// AppButton — one button, six variants, three sizes. Processing shows a spinner and disables it.
// AppButton({text, variant:'Primary|Error|Elevator|Outline|ErrorOutline|Text', size:'Large|Medium|Small', enabled, processing, leftIcon, rightIcon, fullWidth, onclick, type, id, attrs})
function AppButton(o){
 const v=(o.variant||'Primary').toLowerCase(),s=(o.size||'Large').toLowerCase();
 const active=o.enabled!==false&&!o.processing;
 const cls=['btn','btn-'+v,'btn-'+s,o.fullWidth?'btn-full':'',o.processing?'busy':''].filter(Boolean).join(' ');
 const inner=o.processing?'<span class=spin></span>':`${o.leftIcon?Icon(o.leftIcon,s==='large'?18:16):''}${o.text?`<span>${o.text}</span>`:''}${o.rightIcon?Icon(o.rightIcon,16):''}`;
 return `<button type=${o.type||'button'} class="${cls}"${o.id?` id=${o.id}`:''}${active?'':' disabled'}${o.onclick?` onclick="${o.onclick}"`:''}${o.title?` title="${o.title}"`:''} ${o.attrs||''}>${inner}</button>`}
