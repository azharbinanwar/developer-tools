// AppTextField — a filled field: the fill is the field, no border, no focus ring.
// AppTextField({id, value, placeholder, multiline, rows, leading, trailing, oninput, onkeydown, attrs, readonly, bad})
function AppTextField(o){
 const a=`${o.id?` id=${o.id}`:''}${o.placeholder?` placeholder="${o.placeholder}"`:''}${o.oninput?` oninput="${o.oninput}"`:''}${o.onkeydown?` onkeydown="${o.onkeydown}"`:''}${o.readonly?' readonly':''} spellcheck=false ${o.attrs||''}`;
 const f=o.multiline?`<textarea rows=${o.rows||3}${a}>${o.value||''}</textarea>`:`<input${a} value="${o.value||''}">`;
 return `<label class="field${o.multiline?' multi':''}${o.bad?' bad':''}${o.mono?' mono':''}"${o.wrapId?` id=${o.wrapId}`:''}${o.style?` style="${o.style}"`:''}>${o.leading?`<span class=field-ico>${Icon(o.leading,20)}</span>`:''}${f}${o.trailing?`<span class=field-ico>${o.trailing}</span>`:''}</label>`}

// AppChip — a pill; selected = primary wash + semibold.
function AppChip(o){return `<span class="chip${o.selected?' sel':''}${o.enabled===false?' off':''}"${o.onclick?` onclick="${o.onclick}" role=button tabindex=0`:''}>${o.icon?Icon(o.icon,16):''}${o.label}</span>`}

// AppSwitch — M3 switch, 52×32 scaled .85, in a 52×48 hit area.
function AppSwitch(o){return `<span class="switch${o.checked?' on':''}${o.enabled===false?' off':''}"${o.id?` id=${o.id}`:''} role=switch aria-checked=${!!o.checked}${o.onchange?` onclick="${o.onchange}"`:''}><span class=track><span class=thumb></span></span></span>`}

// Radio — the option mark the Run tab's choices use
const Radio=on=>`<span class="radio${on?' on':''}"></span>`;
