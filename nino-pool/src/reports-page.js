// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bildirimleri okuma sayfası (/reports). Sayfa herkese açıktır ama içinde veri yoktur; veriler EXPORT_TOKEN ile
// /v1/reports'tan çekilir. Anahtar yalnız bu tarayıcıda (localStorage) tutulur.
export const REPORTS_PAGE = `<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Nino Bildirimleri</title>
<style>
:root{color-scheme:light dark;--bg:#f5f6f8;--card:#fff;--text:#0a1430;--muted:#5b6478;--line:#e3e6ec;--accent:#2d8cff}
@media (prefers-color-scheme:dark){:root{--bg:#0b1020;--card:#151b2e;--text:#eef1f7;--muted:#9aa3b8;--line:#262e45}}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif}
main{max-width:860px;margin:0 auto;padding:24px 16px}h1{font-size:26px;margin:0 0 16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin:0 0 12px}
.meta{color:var(--muted);font-size:13px;display:flex;gap:10px;flex-wrap:wrap}.text{white-space:pre-wrap;margin:8px 0}
.imgs{display:flex;gap:8px;flex-wrap:wrap}.imgs img{max-width:260px;max-height:200px;border-radius:8px;border:1px solid var(--line);cursor:zoom-in}
button,input{font:inherit;border-radius:8px;border:1px solid var(--line);padding:8px 12px;background:var(--card);color:var(--text)}
button.primary{background:var(--accent);color:#fff;border-color:var(--accent)}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.pill{font-size:12px;padding:2px 8px;border-radius:99px;border:1px solid var(--line)}.new{border-color:var(--accent);color:var(--accent)}
pre{max-height:300px;overflow:auto;background:var(--bg);padding:8px;border-radius:8px;font-size:12px;white-space:pre-wrap}
</style></head><body><main>
<h1>Nino Bildirimleri</h1>
<div class="card row" id="login"><input id="token" type="password" placeholder="Yönetici anahtarı (EXPORT_TOKEN)" style="flex:1;min-width:200px">
<button class="primary" id="go">Göster</button></div>
<div id="list"></div><div class="row"><button id="more" hidden>Daha eski</button></div>
</main><script>
var token=localStorage.getItem('ninoReportsToken')||'',before='';
var $=function(id){return document.getElementById(id)};$('token').value=token;
function api(path,opt){opt=opt||{};opt.headers={authorization:'Bearer '+token};return fetch(path,opt)}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
async function load(reset){
  if(reset){before='';$('list').innerHTML=''}
  var r=await api('/v1/reports?limit=30'+(before?'&before='+before:''));
  if(r.status===401){$('list').innerHTML='<div class="card">Anahtar yanlış.</div>';return}
  var data=await r.json();localStorage.setItem('ninoReportsToken',token);
  data.reports.forEach(function(x){
    var d=document.createElement('div');d.className='card';
    d.innerHTML='<div class="meta"><span class="pill '+(x.status==='new'?'new':'')+'">'+esc(x.status)+'</span><span>'+new Date(x.created*1000).toLocaleString('tr-TR')+'</span><span>'+esc(x.platform)+' '+esc(x.app)+'</span><span>'+esc(x.language)+'</span>'+(x.contact?'<span>İletişim: '+esc(x.contact)+'</span>':'')+'</div>'
      +(x.device?'<div class="meta" style="margin-top:6px">'+esc(x.device).split(' | ').map(function(v){return '<span>'+v+'</span>'}).join('')+'</div>':'')
      +'<div class="text">'+esc(x.text)+'</div><div class="imgs"></div>'
      +'<div class="row" style="margin-top:8px">'+(x.log_length?'<button data-log>Günlüğü göster</button>':'')+'<button data-s="seen">Görüldü</button><button data-s="done">Çözüldü</button></div><pre hidden></pre>';
    for(var i=0;i<x.images;i++)(function(i){api('/v1/reports/'+x.id+'/images/'+i).then(function(r){return r.blob()}).then(function(b){
      var img=document.createElement('img');img.src=URL.createObjectURL(b);img.onclick=function(){window.open(img.src)};d.querySelector('.imgs').appendChild(img)})})(i);
    d.querySelectorAll('[data-s]').forEach(function(b){b.onclick=async function(){await api('/v1/reports/'+x.id+'/status',{method:'POST',body:b.dataset.s});d.querySelector('.pill').textContent=b.dataset.s}});
    var lb=d.querySelector('[data-log]');if(lb)lb.onclick=async function(){var r=await api('/v1/reports/'+x.id);var j=await r.json();var p=d.querySelector('pre');p.textContent=j.report.log;p.hidden=!p.hidden};
    $('list').appendChild(d);before=x.created});
  $('more').hidden=data.reports.length<30;
  if(!data.reports.length&&!before)$('list').innerHTML='<div class="card">Henüz bildirim yok.</div>';
}
$('go').onclick=function(){token=$('token').value.trim();load(true)};$('more').onclick=function(){load(false)};
if(token)load(true);
</script></body></html>`;
