// SPDX-License-Identifier: AGPL-3.0-only
// Nino otomatik teşhis: günlük özet sayfası (GET /teshis). Sayfa veri içermez; panel anahtarıyla
// /v1/diagnoses/daily'den çeker. Dikkat: şablon dizgisi; içinde ters eğik çizgi, ters tırnak, dolar-süslü parantez yok.
export const DIAG_PAGE = `<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><meta name="color-scheme" content="light dark"><title>Nino Teşhis</title>
<style>
:root{--bg:#F3F5FA;--card:#FFFFFF;--ink:#0A1430;--soft:#566180;--line:#E2E7F0;--accent:#1E6FE8;--warn:#A65F00;--bad:#C4262C;--chip:#E8EDF5}
@media (prefers-color-scheme: dark){:root{--bg:#0A0F1E;--card:#121930;--ink:#EDF1FA;--soft:#A5B0C8;--line:#232C47;--accent:#3D83EA;--warn:#E3A541;--bad:#F2777A;--chip:#1E2742}}
*{box-sizing:border-box}[hidden]{display:none!important}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-variant-numeric:tabular-nums}
main{max-width:980px;margin:0 auto;padding:20px 16px 48px}
h1{font-size:22px;margin:0}h2{font-size:16px;margin:0}
header{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin-bottom:16px}header .grow{flex:1;min-width:160px}
.sub{color:var(--soft);font-size:13px}
input,button{font:inherit;min-height:40px;border-radius:10px;border:1px solid var(--line);padding:0 12px;background:var(--card);color:var(--ink)}
button{cursor:pointer;font-weight:600}button.primary{background:var(--accent);border-color:var(--accent);color:#fff}
a{color:var(--accent)}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin:0 0 12px}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:baseline}
.n{font-size:22px;font-weight:750;margin-left:auto}
.chip{display:inline-block;font-size:12px;padding:1px 8px;border-radius:99px;background:var(--chip);color:var(--soft);margin:2px 4px 2px 0}
.chip.new{background:var(--accent);color:#fff}
.sum{margin:10px 0 0;padding:10px 12px;border-left:3px solid var(--accent);background:var(--bg);border-radius:6px}
.cause{margin:8px 0 0;font-size:14px}.cause b{font-weight:650}
details{margin-top:10px}summary{cursor:pointer;color:var(--soft);font-size:13px}
.kv{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:4px 12px;font-size:12.5px;margin-top:8px}
.kv span{color:var(--soft)}
.trail{font:12px ui-monospace,SFMono-Regular,Menlo,monospace;margin-top:8px;white-space:pre-wrap;overflow-wrap:anywhere}
.empty{color:var(--soft);text-align:center;padding:30px 10px}
.msg{color:var(--bad);font-size:13px;min-height:18px}
</style></head><body><main>
<header><div class="grow"><h1>Otomatik teşhis</h1><div class="sub" id="sub">Uygulamaların kendi fark edip bildirdiği sorunlar, gün gün</div></div>
<input id="day" type="date" aria-label="Gün"><button id="sumBtn" type="button">Özetleri yaz</button><a href="/panel">Panel</a></header>
<div class="card" id="gate" hidden><div class="row"><input id="key" type="password" placeholder="Panel anahtarı" aria-label="Panel anahtarı" style="flex:1;min-width:200px"><button class="primary" id="go" type="button">Aç</button></div><div class="msg" id="msg" role="alert"></div></div>
<div id="list"></div>
</main><script>
var $=function(id){return document.getElementById(id)};
var key='';try{key=localStorage.getItem('ninoPanelKey')||''}catch(e){}
function esc(s){return String(s==null?'':s).split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;').split('"').join('&quot;')}
function fmt(v){return Number(v||0).toLocaleString('tr-TR')}
var NAMES={mac:'Mac',windows:'Windows',linux:'Linux',android:'Android',ios:'iPhone / iPad',androidtv:'Android TV',webos:'LG webOS',tizen:'Samsung Tizen'};
function today(){var d=new Date(Date.now()+3*3600*1000);return d.toISOString().slice(0,10)}
$('day').value=today();
function api(path,opt){opt=opt||{};opt.headers={authorization:'Bearer '+key};return fetch(path,opt)}
function gate(show,text){$('gate').hidden=!show;$('msg').textContent=text||''}
$('go').onclick=function(){key=$('key').value.trim();try{localStorage.setItem('ninoPanelKey',key)}catch(e){}load()};
$('day').onchange=load;
$('sumBtn').onclick=async function(){$('sumBtn').disabled=true;$('sumBtn').textContent='Yazılıyor…';
 try{var r=await api('/v1/diagnoses/summarize',{method:'POST'});var d=await r.json();$('sub').textContent=r.ok?fmt(d.summarized)+' grup özetlendi'+(d.failed?', '+fmt(d.failed)+' grup yazılamadı':''):'Özet yazılamadı ('+r.status+')'}catch(e){$('sub').textContent='Özet yazılamadı'}
 $('sumBtn').disabled=false;$('sumBtn').textContent='Özetleri yaz';load()};
function sample(s){
 var kv=Object.keys(s.state||{}).map(function(k){return '<div><span>'+esc(k)+'</span> '+esc(s.state[k])+'</div>'}).join('');
 var tv=s.tv&&(s.tv.brand||s.tv.model)?'<div><span>TV</span> '+esc([s.tv.brand,s.tv.model,s.tv.app].filter(Boolean).join(' · '))+'</div>':'';
 var ver=Object.keys(s.ver||{}).map(function(k){return '<div><span>'+esc(k)+'</span> '+esc(s.ver[k])+'</div>'}).join('');
 var trail=(s.trail||[]).map(function(t){return (t[0]+'s').padStart(6,' ')+'  '+t[1]+(t.length>2?' '+t[2]:'')}).join('<br>');
 var at=new Date(s.at*1000).toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'});
 return '<details><summary>'+esc(at)+' · '+esc(s.sev)+' · '+esc(s.text)+' · '+esc(s.app)+(s.os?' · '+esc(s.os):'')+(s.game?' · '+esc(s.gameName||s.game):'')+'</summary>'+
  '<div class="kv">'+kv+tv+ver+'</div>'+(trail?'<div class="trail">'+esc(trail).split('&lt;br&gt;').join('<br>')+'</div>':'')+'</details>'}
function group(g){
 var causes=g.causes.slice().sort(function(a,b){return b.n-a.n}).map(function(c){return '<div class="cause"><b>'+fmt(c.n)+'×</b> '+esc(c.text)+' <span class="chip">'+esc(c.cause)+'</span><span class="chip">'+esc(c.app||'?')+'</span></div>'}).join('');
 return '<div class="card"><div class="row"><h2>'+esc(g.title)+'</h2>'+(g.fresh?'<span class="chip new">yeni</span>':'')+'<span class="chip">'+esc(NAMES[g.platform]||g.platform)+'</span>'+
  (g.model?'<span class="chip">'+esc(g.model)+'</span>':'')+'<span class="n">'+fmt(g.n)+'</span></div>'+
  (g.summary?'<div class="sum">'+esc(g.summary)+'</div>':'')+causes+(g.samples||[]).map(sample).join('')+
  '<div class="sub" style="margin-top:8px">İlk görülme: '+(g.firstSeen?esc(new Date(g.firstSeen*1000).toLocaleString('tr-TR'))+' ('+esc(g.firstApp)+')':'–')+'</div></div>'}
async function load(){
 if(!key){gate(true,'');return}
 var r=null;try{r=await api('/v1/diagnoses/daily?day='+encodeURIComponent($('day').value||today()))}catch(e){r=null}
 if(!r){gate(true,'Sunucuya ulaşılamadı.');return}
 if(r.status===401){gate(true,'Anahtar kabul edilmedi.');return}
 var d=await r.json();gate(false);
 if(!d.ready){$('list').innerHTML='<div class="card empty">Teşhis tabloları henüz kurulmadı (sunucuda 0019 migration gerekiyor).</div>';return}
 $('sub').textContent=fmt(d.total)+' bildirim, '+fmt(d.groups.length)+' sorun grubu';
 $('list').innerHTML=d.groups.length?d.groups.map(group).join(''):'<div class="card empty">Bu gün otomatik teşhis yok.</div>'}
load();
</script></body></html>`;
