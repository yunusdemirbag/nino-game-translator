// SPDX-License-Identifier: AGPL-3.0-only
// Nino paneli (GET /panel). Sayfa veri içermez; anahtarla /v1/stats'tan çeker, 15 saniyede bir yeniler.
// "Sağlık" bölümü (ölçüm: hata ve hız) /v1/events/stats'tan dakikada bir çekilir.
// Dikkat: sayfa bir şablon dizgisinin içinde durur; içinde ters eğik çizgi, ters tırnak ya da dolar-süslü parantez
// kullanma. Grafikler elle çizilen satır içi SVG'dir (CSP dışarıdan hiçbir şey yüklemeye izin vermez).
export const ADMIN_PAGE = `<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>Nino Panel</title>
<style>
:root{--bg:#F3F5FA;--card:#FFFFFF;--ink:#0A1430;--soft:#566180;--line:#E2E7F0;--grid:#ECEFF5;--accent:#1E6FE8;--accent-ink:#FFFFFF;
--series:#2a78d6;--series-hi:#0F4A9C;--track:#E4EBF7;--quiet:#E8EDF5;--warn:#A65F00;--bad:#C4262C;--tip:#0A1430;--tip-ink:#FFFFFF;--hero-line:transparent}
@media (prefers-color-scheme: dark){:root{--bg:#0A0F1E;--card:#121930;--ink:#EDF1FA;--soft:#A5B0C8;--line:#232C47;--grid:#1B2440;--accent:#3D83EA;--accent-ink:#FFFFFF;
--series:#3987e5;--series-hi:#9CC6F7;--track:#1E2947;--quiet:#1E2742;--warn:#E3A541;--bad:#F2777A;--tip:#EDF1FA;--tip-ink:#0A1430;--hero-line:rgba(255,255,255,.10)}}
*{box-sizing:border-box}
[hidden]{display:none!important}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;font-variant-numeric:tabular-nums;-webkit-font-smoothing:antialiased}
h1,h2,h3,p{margin:0}
main{max-width:1200px;margin:0 auto;padding:max(16px,env(safe-area-inset-top)) max(16px,env(safe-area-inset-right)) max(40px,env(safe-area-inset-bottom)) max(16px,env(safe-area-inset-left))}
header{display:flex;align-items:center;gap:12px}
header h1{font-size:20px;letter-spacing:-.3px;line-height:1.2}
header .sub{color:var(--soft);font-size:12.5px}
header .sub.warn{color:var(--warn)}
header .grow{flex:1;min-width:0}
.logo{flex:none;width:40px;height:40px;border-radius:11px;background:linear-gradient(135deg,#0A1430,#1E6FE8);display:grid;place-items:center;color:#fff;font-weight:800;font-size:18px}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:44px;padding:0 18px;border:0;border-radius:12px;font:inherit;font-weight:600;font-size:14px;cursor:pointer;text-decoration:none;background:var(--quiet);color:var(--ink)}
.btn.primary{background:var(--accent);color:var(--accent-ink)}
.btn:focus-visible,input:focus-visible,.chart:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.sec{font-size:15px;font-weight:700;letter-spacing:-.1px;margin:28px 2px 10px}
.stack{display:grid;gap:12px}
.stack>*,.tiles>*,.cols>*,.minis>*,.split>*,.hero>*{min-width:0}
.tiles{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(148px,1fr))}
.cols{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(260px,1fr))}
.minis{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(230px,1fr))}
.split{display:grid;gap:12px;grid-template-columns:2fr 1fr}
.split.rev{grid-template-columns:1fr 2fr}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px}
.k{color:var(--soft);font-size:13px;font-weight:600}
.v{font-size:clamp(22px,6.4vw,30px);font-weight:750;letter-spacing:-.6px;line-height:1.15;margin-top:6px;overflow-wrap:anywhere}
.s{color:var(--soft);font-size:12.5px;margin-top:4px}
.card .btn{margin-top:12px}
.head{display:flex;align-items:baseline;justify-content:space-between;gap:10px}
.head .now{font-size:20px;font-weight:750;letter-spacing:-.3px;white-space:nowrap}
.head .now small{font-size:12px;font-weight:500;color:var(--soft);margin-left:5px;letter-spacing:0}
.note{color:var(--soft);font-size:12.5px;margin-top:8px}
.note:empty{display:none}

.hero{background:linear-gradient(135deg,#0A1430 0%,#12265A 62%,#1B4FAE 135%);color:#fff;border:1px solid var(--hero-line);border-radius:20px;padding:22px;display:grid;gap:0 28px;grid-template-columns:1fr 1.15fr 1fr}
.hero h3{font-size:13px;font-weight:600;color:rgba(255,255,255,.72);margin-bottom:10px}
.hero .label{display:flex;align-items:center;gap:8px;font-size:14px;color:rgba(255,255,255,.78)}
.hero .big{font-size:clamp(60px,19vw,92px);font-weight:800;letter-spacing:-.04em;line-height:1;margin:8px 0 10px}
.dot{flex:none;width:10px;height:10px;border-radius:50%;background:#35E39B;animation:pulse 1.8s infinite}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(53,227,155,.7)}70%{box-shadow:0 0 0 12px rgba(53,227,155,0)}100%{box-shadow:0 0 0 0 rgba(53,227,155,0)}}
@media (prefers-reduced-motion: reduce){.dot{animation:none}}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{background:rgba(255,255,255,.13);border-radius:999px;padding:4px 11px;font-size:13px}
.hero .part{border-left:1px solid rgba(255,255,255,.14);padding-left:28px}
.pk{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
.pk b{display:block;font-size:clamp(28px,8.4vw,40px);font-weight:750;letter-spacing:-.03em;line-height:1.1}
.pk span{display:block;font-size:12.5px;color:rgba(255,255,255,.72);margin-top:2px}
.hero p{font-size:12.5px;color:rgba(255,255,255,.72);margin-top:10px}
.hero p+p{margin-top:2px}
.games>div>div{display:flex;justify-content:space-between;gap:12px;padding:7px 0;border-bottom:1px solid rgba(255,255,255,.12);font-size:14px}
.games>div>div:last-child{border-bottom:0}
.games span{min-width:0;overflow-wrap:anywhere}

.chart{position:relative;overflow:hidden;margin-top:10px;border-radius:6px;cursor:crosshair;touch-action:pan-y;-webkit-tap-highlight-color:transparent}
.chart svg{position:absolute;left:0;top:0;display:block}
.chart .g{stroke:var(--grid);stroke-width:1}
.chart .base{stroke:var(--line);stroke-width:1}
.chart .ref{stroke:var(--soft);stroke-width:1}
.chart .ax{fill:var(--soft);font-size:11px}
.chart .val{fill:var(--ink);font-size:12px;font-weight:700;paint-order:stroke;stroke:var(--card);stroke-width:4px;stroke-linejoin:round}
.chart .b{fill:var(--series)}
.chart .b.z{opacity:.45}
.chart .b.hi,.chart .b.on{fill:var(--series-hi)}
.chart .band{fill:var(--grid);opacity:0}
.chart .band.on{opacity:1}
.empty{display:grid;place-items:center;text-align:center;min-height:96px;margin-top:10px;padding:14px;border:1px dashed var(--line);border-radius:12px;color:var(--soft);font-size:13px}
#tip{position:absolute;z-index:20;left:0;top:0;pointer-events:none;background:var(--tip);color:var(--tip-ink);border-radius:10px;padding:7px 10px;font-size:12.5px;line-height:1.35;max-width:230px;box-shadow:0 4px 14px rgba(10,20,48,.16)}
#tip b{display:block;font-size:14px}
#tip span{opacity:.82}

.list{margin-top:6px}
.row{padding:8px 0 0}
.rt{display:flex;align-items:baseline;gap:8px;font-size:14px}
.rt span{flex:1;min-width:0;overflow-wrap:anywhere}
.rt em{font-style:normal;font-size:11px;font-weight:600;color:var(--soft);border:1px solid var(--line);border-radius:999px;padding:0 6px;margin-left:6px;white-space:nowrap}
.rt b{font-weight:650;white-space:nowrap}
.rt i{font-style:normal;color:var(--soft);font-size:12.5px;min-width:34px;text-align:right;white-space:nowrap}
.track{height:6px;border-radius:99px;background:var(--track);overflow:hidden;margin-top:6px}
.track span{display:block;height:100%;border-radius:99px;background:var(--series)}
.none{color:var(--soft);font-size:13px;padding-top:10px}
.meter{height:10px;border-radius:99px;background:var(--track);overflow:hidden;margin-top:12px}
.meter i{display:block;height:100%;width:0;border-radius:99px;background:var(--series);transition:width .4s}
.meter.warn i{background:var(--warn)}
.meter.bad i{background:var(--bad)}
.flag{font-weight:650}
.flag.warn{color:var(--warn)}
.flag.bad{color:var(--bad)}

.seg{display:inline-flex;background:var(--quiet);border-radius:12px;padding:3px;gap:2px;margin-left:10px;vertical-align:middle}
.seg button{border:0;background:transparent;color:var(--ink);font:inherit;font-size:13px;font-weight:600;min-height:32px;padding:0 12px;border-radius:9px;cursor:pointer}
.seg button[aria-pressed=true]{background:var(--card);box-shadow:0 1px 3px rgba(10,20,48,.12)}
.scroll{overflow-x:auto;margin-top:8px;-webkit-overflow-scrolling:touch}
.tbl{width:100%;border-collapse:collapse;font-size:13.5px;white-space:nowrap}
.tbl th{text-align:right;color:var(--soft);font-weight:600;font-size:12px;padding:6px 8px;border-bottom:1px solid var(--line)}
.tbl td{text-align:right;padding:7px 8px;border-bottom:1px solid var(--grid)}
.tbl th:first-child,.tbl td:first-child{text-align:left;padding-left:0}
.tbl tr:last-child td{border-bottom:0}
.tbl td.bad{color:var(--bad);font-weight:650}
.tbl td.warn{color:var(--warn);font-weight:650}
.tbl small{color:var(--soft);font-size:11.5px}
.rec{display:flex;gap:10px;align-items:baseline;padding:8px 0;border-bottom:1px solid var(--grid);font-size:13.5px}
.rec:last-child{border-bottom:0}
.rec time{color:var(--soft);font-size:12px;min-width:84px}
.rec span{flex:1;min-width:0;overflow-wrap:anywhere}
.rec code{font:600 12.5px ui-monospace,SFMono-Regular,Menlo,monospace}
.rec small{display:block;color:var(--soft);font-size:12px}

#gate{max-width:400px;margin:12vh auto 0;padding:0 max(16px,env(safe-area-inset-right)) 0 max(16px,env(safe-area-inset-left))}
#gate .card{padding:26px 22px;text-align:center}
#gate .logo{margin:0 auto 12px}
#gate h1{font-size:22px;letter-spacing:-.3px}
#gate p{color:var(--soft);font-size:14px;margin-top:6px}
#gate input{width:100%;min-height:48px;padding:0 14px;border:1px solid var(--line);border-radius:12px;font:inherit;font-size:16px;margin:16px 0 0;background:var(--bg);color:var(--ink)}
#gate .msg{color:var(--bad);font-size:13px;min-height:18px;margin-top:8px}
#gate .btn{width:100%;margin-top:8px}

@media (max-width:900px){
 .hero{grid-template-columns:1fr;padding:20px 18px}
 .hero .part{border-left:0;padding-left:0;border-top:1px solid rgba(255,255,255,.14);margin-top:18px;padding-top:16px}
 .split,.split.rev{grid-template-columns:1fr}
}
@media (max-width:520px){.tiles>:last-child:nth-child(odd){grid-column:1/-1}}
@media (min-width:901px){main{padding-left:max(24px,env(safe-area-inset-left));padding-right:max(24px,env(safe-area-inset-right));padding-top:max(24px,env(safe-area-inset-top))}header h1{font-size:22px}.card{padding:18px}}
</style></head><body>
<div id="gate" hidden><div class="card"><div class="logo" aria-hidden="true">N</div><h1>Nino Panel</h1><p>Panel anahtarını gir (bu cihazda hatırlanır).</p>
<input id="key" type="password" placeholder="Anahtar" aria-label="Panel anahtarı" autocomplete="off" autocapitalize="off" spellcheck="false">
<div class="msg" id="gateMsg" role="alert"></div><button id="go" class="btn primary" type="button">Aç</button></div></div>

<main id="app" hidden>
<header><div class="logo" aria-hidden="true">N</div><div class="grow"><h1>Nino Panel</h1><div class="sub" id="when">Canlı · 15 saniyede bir yenilenir</div></div>
<button id="out" class="btn" type="button">Çıkış</button></header>

<h2 class="sec">Canlı</h2>
<section class="hero">
 <div><div class="label"><span class="dot" aria-hidden="true"></span>Şu an oynayan</div><div class="big" id="now">–</div><div class="chips" id="nowPlat"></div></div>
 <div class="part"><h3>En çok aynı anda oynayan</h3>
  <div class="pk"><div><b id="pkToday">–</b><span>Bugün</span></div><div><b id="pkWeek">–</b><span>Son 7 gün</span></div><div><b id="pkAll">–</b><span>Rekor</span></div></div>
  <p id="pkWhen"></p><p id="pkSince"></p></div>
 <div class="part games"><h3>Şu an oynanan oyunlar</h3><div id="games"></div></div>
</section>

<h2 class="sec">Oyuncular</h2>
<section class="stack">
 <div class="card"><div class="k">Aynı anda oynayan (son 48 saat)</div><div class="s">Her saatin en yüksek oyuncu sayısı</div><div id="cHours"></div><div class="note" id="cHoursNote"></div></div>
 <div class="minis">
  <div class="card"><div class="head"><div class="k">Günlük açan</div><div class="now" id="vActive"></div></div><div class="s">O gün uygulamayı açan farklı kurulum</div><div id="cActive"></div><div class="note" id="cActiveNote"></div></div>
  <div class="card"><div class="head"><div class="k">Günlük oynayan</div><div class="now" id="vPlayed"></div></div><div class="s">O gün çeviri yapan farklı kurulum</div><div id="cPlayed"></div><div class="note" id="cPlayedNote"></div></div>
  <div class="card"><div class="head"><div class="k">Yeni kurulum</div><div class="now" id="vFresh"></div></div><div class="s">O gün ilk kez açılan kurulum</div><div id="cFresh"></div><div class="note" id="cFreshNote"></div></div>
  <div class="card"><div class="head"><div class="k">Günün en yükseği</div><div class="now" id="vPeak"></div></div><div class="s">O gün aynı anda en çok oynayan</div><div id="cPeak"></div><div class="note" id="cPeakNote"></div></div>
 </div>
</section>

<h2 class="sec">Kurulumlar</h2>
<section class="stack">
 <div class="tiles">
  <div class="card"><div class="k">Toplam kurulum</div><div class="v" id="inst">–</div><div class="s" id="instNew"></div></div>
  <div class="card"><div class="k">Son 24 saatte açan</div><div class="v" id="a24">–</div><div class="s">Farklı kurulum</div></div>
  <div class="card"><div class="k">İndirme (GitHub)</div><div class="v" id="dl">–</div><div class="s" id="dlBy"></div></div>
  <div class="card"><div class="k">En yeni sürüm</div><div class="v" id="latest">–</div><div class="s">GitHub</div></div>
 </div>
 <div class="cols">
  <div class="card"><div class="k">Kurulumlar (platform)</div><div class="list" id="plat"></div></div>
  <div class="card"><div class="k">Sürümler (son 7 gün)</div><div class="s" id="verNote">Son 7 günde açılan kurulumların sürümü</div><div class="list" id="vers"></div></div>
  <div class="card"><div class="k">Kullanıcı dilleri</div><div class="s">Uygulamada seçilen dil</div><div class="list" id="ulangs"></div></div>
  <div class="card"><div class="k">İndirmeler (dosyaya göre)</div><div class="s">GitHub sürüm dosyaları</div><div class="list" id="dlList"></div></div>
 </div>
</section>

<h2 class="sec">TV'ler</h2>
<section class="stack">
 <div class="tiles">
  <div class="card"><div class="k">Nino kurulu TV</div><div class="v" id="tvTotal">–</div><div class="s" id="tvNote">TV uygulamasının bildirdiği farklı TV</div></div>
  <div class="card"><div class="k">Android TV / Google TV</div><div class="v" id="tvA">–</div><div class="s">TV</div></div>
  <div class="card"><div class="k">Samsung</div><div class="v" id="tvS">–</div><div class="s">TV ve akıllı monitör</div></div>
  <div class="card"><div class="k">LG</div><div class="v" id="tvL">–</div><div class="s">TV</div></div>
 </div>
 <div class="cols">
  <div class="card"><div class="k">Android TV / Google TV modelleri</div><div class="list" id="tvModelsA"></div></div>
  <div class="card"><div class="k">Samsung modelleri</div><div class="list" id="tvModelsS"></div></div>
  <div class="card"><div class="k">LG modelleri</div><div class="list" id="tvModelsL"></div></div>
  <div class="card"><div class="k">TV uygulaması sürümleri</div><div class="list" id="tvVers"></div></div>
 </div>
</section>

<h2 class="sec">Çeviri</h2>
<section class="stack">
 <div class="tiles">
  <div class="card"><div class="k">Çevrilen satır</div><div class="v" id="lines">–</div><div class="s" id="words"></div></div>
  <div class="card"><div class="k">Gözden geçirilen</div><div class="v" id="rev">–</div><div class="s">Bağlamla düzeltilip onaylanan</div></div>
  <div class="card"><div class="k">Toplanan İngilizce satır</div><div class="v" id="pool">–</div><div class="s" id="poolSeen"></div></div>
 </div>
 <div class="split">
  <div class="card"><div class="k">Saatlik çeviri (son 24 saat)</div><div class="s" id="today"></div><div id="cTr"></div></div>
  <div class="card"><div class="k">Diller (çeviri)</div><div class="list" id="langs"></div></div>
 </div>
</section>

<h2 class="sec">Maliyet</h2>
<section class="split rev">
 <div class="card"><div class="k">Bugünkü çeviri harcaması</div><div class="v" id="spend">–</div><div class="meter" id="spendMeter"><i id="spendBar"></i></div><div class="s" id="spendCap"></div><div class="s" id="spendAsk"></div></div>
 <div class="card"><div class="k">Çeviri harcaması (son 7 gün)</div><div class="s" id="weekSum"></div><div id="cWeek"></div></div>
</section>

<h2 class="sec">Destek</h2>
<section class="cols">
 <div class="card"><div class="k">Sorun bildirimi</div><div class="v" id="rep">–</div><div class="s" id="repNew"></div><a class="btn" href="/reports">Bildirimleri aç</a></div>
 <div class="card"><div class="k">Nino'ya Sor (bugün)</div><div class="v" id="ask">–</div><div class="s" id="askCost"></div><div class="s" id="askMix"></div><div class="s" id="askModels"></div><div class="s" id="askSpend"></div></div>
</section>
<h2 class="sec">Sağlık <span class="seg" role="group" aria-label="Zaman aralığı"><button type="button" data-days="1" aria-pressed="false">Bugün</button><button type="button" data-days="7" aria-pressed="true">7 gün</button><button type="button" data-days="30" aria-pressed="false">30 gün</button></span></h2>
<section class="stack" id="health">
 <div class="note" id="hNote"></div>
 <div class="tiles">
  <div class="card"><div class="k">Çökmesiz açılış</div><div class="v" id="hCrashFree">–</div><div class="s" id="hCrashes"></div></div>
  <div class="card"><div class="k">Hata (100 oturumda)</div><div class="v" id="hErr">–</div><div class="s" id="hErrN"></div></div>
  <div class="card"><div class="k">PS5 bağlantı başarısı</div><div class="v" id="hPs5">–</div><div class="s" id="hPs5N"></div></div>
  <div class="card"><div class="k">TV bağlantı başarısı</div><div class="v" id="hTv">–</div><div class="s" id="hTvN"></div></div>
  <div class="card"><div class="k">Çeviri gecikmesi</div><div class="v" id="hLat">–</div><div class="s" id="hLatN"></div></div>
 </div>
 <div class="split">
  <div class="card"><div class="k">Günlük hata (100 oturumda)</div><div class="s" id="hDailyNote">Yakalanan hatalar / çeviri oturumları</div><div id="cHealth"></div></div>
  <div class="card"><div class="k">En sık sorunlar</div><div class="s">Çökme, hata ve bağlantı sorunları</div><div class="list" id="hProblems"></div></div>
 </div>
 <div class="card"><div class="k">Platform ve sürüm</div><div class="s">Çökmesiz: çökmeden kapanan açılışlar · PS5 / TV: bağlantı denemelerinin başarısı</div><div class="scroll" id="hVersions"></div></div>
 <div class="card"><div class="k">Çeviri ve okuma hızı</div><div class="s">Bütün platformlar; p50 ortanca, p90 ve p99 yavaş uçlar</div><div class="scroll" id="hTimings"></div></div>
 <div class="card"><div class="k">Gecikme (platforma göre)</div><div class="s">Satırın okunmasından çevirisinin ekranda görünmesine</div><div class="scroll" id="hLatency"></div></div>
 <div class="cols">
  <div class="card"><div class="k">TV markaları</div><div class="s">Bağlantı başarısı</div><div class="list" id="hTvBrands"></div></div>
  <div class="card"><div class="k">PS5 bağlantı yolu</div><div class="s">Ev ağı / internet / Xbox</div><div class="list" id="hVia"></div></div>
  <div class="card"><div class="k">Oyunlar</div><div class="s">Çeviri oturumu</div><div class="list" id="hGames"></div></div>
 </div>
 <div class="card"><div class="k">Son çökme ve hatalar</div><div class="s">Son 30 gün, en yeni üstte (kişisel bilgi yok)</div><div class="list" id="hRecent"></div></div>
</section>
<h2 class="sec">TV bağlantıları</h2>
<section class="stack" id="tvlinks">
 <div class="note" id="tlNote"></div>
 <div class="tiles">
  <div class="card"><div class="k">Kopma oranı</div><div class="v" id="tlRate">–</div><div class="s" id="tlRateN"></div></div>
  <div class="card"><div class="k">Kopmadan önce bağlı kalma</div><div class="v" id="tlAfter">–</div><div class="s">Ortalama</div></div>
  <div class="card"><div class="k">Son 24 saatte kopma</div><div class="v" id="tl24">–</div><div class="s" id="tl24N"></div></div>
  <div class="card"><div class="k">Çok kopan kurulum</div><div class="v" id="tlAlertN">–</div><div class="s">1 saatte 3+ ya da 6 saatte 6+ kopma</div></div>
 </div>
 <div class="card"><div class="k">Uyarılar: kısa sürede çok kopan kurulumlar</div><div class="s">Son 6 saat; kurulum kimliği gösterilmez</div><div class="list" id="tlAlerts"></div></div>
 <div class="card"><div class="k">TV modelleri</div><div class="s">Kopma oranı = kopma / başarılı bağlantı · seçili aralık</div><div class="scroll" id="tlModels"></div></div>
 <div class="split">
  <div class="card"><div class="k">Son 24 saatte en çok kopan modeller</div><div class="scroll" id="tlLast24"></div></div>
  <div class="card"><div class="k">Kopma nedenleri</div><div class="list" id="tlReasons"></div></div>
 </div>
 <div class="cols">
  <div class="card"><div class="k">TV uygulaması sürümleri</div><div class="scroll" id="tlApps"></div></div>
  <div class="card"><div class="k">Gönderen platform</div><div class="s">Altyazıyı TV'ye gönderen uygulama (TV'nin kendisi dahil)</div><div class="scroll" id="tlSenders"></div></div>
 </div>
</section>
<h2 class="sec">Otomatik teşhis</h2>
<section class="stack" id="diag">
 <div class="note" id="dgNote"></div>
 <div class="tiles">
  <div class="card"><div class="k">Otomatik bildirim</div><div class="v" id="dgTotal">–</div><div class="s">Seçili aralık</div><a class="btn" href="/teshis">Günlük özet</a></div>
  <div class="card"><div class="k">Yeni çıkan sorun</div><div class="v" id="dgFreshN">–</div><div class="s">Son 48 saatte ilk kez görülen</div></div>
  <div class="card"><div class="k">Sürüm sonrası artış</div><div class="v" id="dgRegN">–</div><div class="s">Yeni sürümde açılış başına 2 kat ve üstü</div></div>
 </div>
 <div class="card"><div class="k">Sürüm sonrası artış</div><div class="s">Aynı platformda en yeni iki sürüm (en az 20 açılış), açılış başına bildirim</div><div class="scroll" id="dgReg"></div></div>
 <div class="split">
  <div class="card"><div class="k">En sık otomatik sorunlar</div><div class="s">Kural · platform · model; en sık sebep</div><div class="list" id="dgTop"></div></div>
  <div class="card"><div class="k">Yeni çıkan sorunlar</div><div class="list" id="dgFresh"></div></div>
 </div>
</section>
</main>
<div id="tip" hidden><b id="tipV"></b><span id="tipL"></span></div>
<script>
var $=function(id){return document.getElementById(id)};
function num(v){v=Number(v);return isFinite(v)?v:0}
function fmt(v){return num(v).toLocaleString('tr-TR')}
function usd(v){return '$'+num(v).toLocaleString('tr-TR',{minimumFractionDigits:2,maximumFractionDigits:2})}
function esc(s){return String(s==null?'':s).split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;').split('"').join('&quot;').split("'").join('&#39;')}
function arr(v){return Array.isArray(v)?v:[]}
function obj(v){return v&&typeof v==='object'?v:{}}
function set(id,text){var e=$(id);if(e)e.textContent=text}
function r2(v){return Math.round(v*100)/100}
function D(t){return new Date(t*1000)}
function hm(t){return D(t).toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'})}
function dShort(t){return D(t).toLocaleDateString('tr-TR',{day:'numeric',month:'short'})}
function dLong(t){return D(t).toLocaleDateString('tr-TR',{day:'numeric',month:'long',weekday:'long'})}
var NAMES={mac:'Mac',windows:'Windows',android:'Android',ios:'iPhone / iPad',tv:'TV',linux:'Linux','':'Bilinmiyor (eski sürüm)'};
var LANGS={tr:'🇹🇷 Türkçe',ar:'🇸🇦 Arapça',hi:'🇮🇳 Hintçe',id:'🇮🇩 Endonezce',th:'🇹🇭 Tayca',vi:'🇻🇳 Vietnamca',ur:'🇵🇰 Urduca',bn:'🇧🇩 Bengalce',ms:'🇲🇾 Malayca',tl:'🇵🇭 Filipince',nl:'🇳🇱 Felemenkçe',en:'🇬🇧 İngilizce',de:'🇩🇪 Almanca',fr:'🇫🇷 Fransızca',es:'🇪🇸 İspanyolca',it:'🇮🇹 İtalyanca',pt:'🇵🇹 Portekizce',ru:'🇷🇺 Rusça',pl:'🇵🇱 Lehçe',fa:'🇮🇷 Farsça',az:'🇦🇿 Azerice',ja:'🇯🇵 Japonca',ko:'🇰🇷 Korece',zh:'🇨🇳 Çince'};
var MONTHS=['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'];
var FROM=['tan','tan','tan','dan','tan','dan','dan','tan','den','den','dan','tan'];
var EARLY='Kayıt yeni başladı; grafik doldukça burada görünecek.';
function platName(p){p=p==null?'':String(p);return esc(NAMES[p]||p)}
function langName(l){l=String(l==null?'':l);return esc(LANGS[l]||LANGS[l.split('-')[0]]||l||'Bilinmiyor')}
function sinceText(t){var d=D(t),m=d.getMonth();
 if(d.getFullYear()!==new Date().getFullYear())return 'Kayıt başlangıcı: '+d.getDate()+' '+MONTHS[m]+' '+d.getFullYear();
 return 'Kayıt '+d.getDate()+' '+MONTHS[m]+"'"+FROM[m]+' beri tutuluyor'}

/* ---------- Giriş ---------- */
var key='';try{key=localStorage.getItem('ninoPanelKey')||''}catch(e){}
function gate(show,msg){$('gate').hidden=!show;$('app').hidden=show;if(show){set('gateMsg',msg||'');hideTip()}}
function enter(){key=$('key').value.trim();if(!key){gate(true,'Önce anahtarı yaz.');return}try{localStorage.setItem('ninoPanelKey',key)}catch(e){}load()}
$('go').onclick=enter;
$('key').addEventListener('keydown',function(e){if(e.key==='Enter')enter()});
$('out').onclick=function(){try{localStorage.removeItem('ninoPanelKey')}catch(e){}key='';$('key').value='';gate(true,'')};
function status(text,warn){var e=$('when');if(!e)return;e.textContent=text;e.className=warn?'sub warn':'sub'}

/* ---------- Grafik: tek seri, çubuk ---------- */
var REG={},TIP={id:null,i:-1};
function scale(mx,target,dec){
 if(!(mx>0))mx=1;
 var raw=mx/target,p=Math.pow(10,Math.floor(Math.log(raw)/Math.LN10)),m=raw/p;
 var step=(m<=1?1:m<=2?2:m<=5?5:10)*p;if(!dec&&step<1)step=1;
 var count=Math.max(1,Math.ceil(mx/step-1e-9)),ticks=[];
 for(var i=0;i<=count;i++)ticks.push(r2(i*step));
 return {top:count*step,ticks:ticks}}
function barPath(x,y,w,h,r){r=Math.max(0,Math.min(r,w/2,h));var b=r2(y+h),x1=r2(x+w);x=r2(x);y=r2(y);
 return 'M'+x+' '+b+'V'+r2(y+r)+'Q'+x+' '+y+' '+r2(x+r)+' '+y+'H'+r2(x1-r)+'Q'+x1+' '+y+' '+x1+' '+r2(y+r)+'V'+b+'Z'}
function anchorAt(cx,w,W){if(cx-w/2<0)return {x:0,a:'start'};if(cx+w/2>W)return {x:W,a:'end'};return {x:r2(cx),a:'middle'}}
function describe(title,slots,tv){
 var lo=null,hi=null,last=null;
 slots.forEach(function(s){if(s.v==null)return;if(!lo||s.v<lo.v)lo=s;if(!hi||s.v>=hi.v)hi=s;last=s});
 if(!last)return title+': henüz kayıt yok.';
 return title+'. En düşük '+tv(lo.v)+', en yüksek '+tv(hi.v)+' ('+hi.t+'), son değer '+tv(last.v)+' ('+last.t+').'}
/* slots: [{v: sayı ya da null (kayıt yok), t: ipucu yazısı, x: eksen yazısı, lv: önem 1-3, d: tarih (ikinci satır)}] */
function chart(id,slots,opts){
 var host=$(id);if(!host)return;
 REG[id]={slots:slots,opts:opts,geo:null};
 host.className='chart';host.setAttribute('role','img');host.setAttribute('tabindex','0');
 host.setAttribute('aria-label',describe(opts.title,slots,opts.tipVal||fmt));
 draw(id)}
function placeholder(id,text){var host=$(id);if(!host)return;delete REG[id];if(TIP.id===id)hideTip();
 host.className='empty';host.removeAttribute('role');host.removeAttribute('tabindex');host.removeAttribute('aria-label');host.style.height='';host.textContent=text}
function draw(id){
 var c=REG[id],host=$(id);if(!c||!host)return;
 var slots=c.slots,o=c.opts,n=slots.length,i;
 var W=Math.max(200,Math.floor(host.clientWidth)||320),H=o.h||150;
 var mx=0;for(i=0;i<n;i++)if(slots[i].v!=null&&slots[i].v>mx)mx=slots[i].v;
 if(o.ref>mx)mx=o.ref;
 var sc=scale(mx,o.ticks||3,o.dec),tf=o.tick||fmt,cw=6.3,lw=1;
 for(i=0;i<sc.ticks.length;i++)lw=Math.max(lw,String(tf(sc.ticks[i])).length);
 var padL=Math.ceil(lw*cw)+10,padR=4,padT=22,padB=o.two?36:22;
 var pw=W-padL-padR,ph=H-padT-padB,sw=pw/n,bw=Math.max(1,Math.min(24,sw-2)),y0=padT+ph,tops=[],mark=-1;
 if(o.mark==='last'){if(n&&slots[n-1].v!=null)mark=n-1}
 else if(o.mark==='max'){var best=0;for(i=0;i<n;i++)if(slots[i].v!=null&&slots[i].v>0&&slots[i].v>=best){best=slots[i].v;mark=i}}
 var s='<svg width="'+W+'" height="'+H+'" viewBox="0 0 '+W+' '+H+'" aria-hidden="true" focusable="false">';
 for(i=0;i<sc.ticks.length;i++){var ty=r2(y0-ph*sc.ticks[i]/sc.top);
  s+='<line class="'+(i?'g':'base')+'" x1="'+padL+'" x2="'+(W-padR)+'" y1="'+ty+'" y2="'+ty+'"/>';
  s+='<text class="ax" x="'+(padL-6)+'" y="'+r2(ty+3.5)+'" text-anchor="end">'+esc(tf(sc.ticks[i]))+'</text>'}
 s+='<rect class="band" id="'+id+'-band" x="0" y="'+padT+'" width="0" height="'+ph+'" rx="3"/>';
 for(i=0;i<n;i++){var v=slots[i].v;if(v==null){tops.push(y0-28);continue}
  var bh=v>0?Math.max(2,ph*v/sc.top):2,bx=padL+i*sw+(sw-bw)/2,by=y0-bh;tops.push(by);
  s+='<path class="b'+(v>0?'':' z')+(i===mark?' hi':'')+'" data-i="'+i+'" d="'+barPath(bx,by,bw,bh,4)+'"/>'}
 if(o.ref>0){var ry=r2(y0-ph*o.ref/sc.top);
  s+='<line class="ref" x1="'+padL+'" x2="'+(W-padR)+'" y1="'+ry+'" y2="'+ry+'"/>';
  if(o.refLabel)s+='<text class="ax" x="'+(padL+4)+'" y="'+r2(ry-5)+'">'+esc(o.refLabel)+'</text>'}
 if(mark>=0&&o.label!==false){var txt=(o.markVal||o.tipVal||fmt)(slots[mark].v),ma=anchorAt(padL+(mark+.5)*sw,txt.length*7+4,W);
  s+='<text class="val" x="'+ma.x+'" y="'+r2(tops[mark]-6)+'" text-anchor="'+ma.a+'">'+esc(txt)+'</text>'}
 var xw=0;for(i=0;i<n;i++)if(slots[i].x)xw=Math.max(xw,String(slots[i].x).length*cw,String(slots[i].d||'').length*cw);
 var level=1;for(var L=3;L>=1;L--){var prev=-1,fits=true;
  for(i=0;i<n;i++){if(!slots[i].x||(slots[i].lv||1)>L)continue;if(prev>=0&&(i-prev)*sw<xw+8){fits=false;break}prev=i}
  if(fits){level=L;break}}
 var lastD=null;
 for(i=0;i<n;i++){var sl=slots[i];if(!sl.x||(sl.lv||1)>level)continue;
  var xa=anchorAt(padL+(i+.5)*sw,xw,W);
  s+='<text class="ax" x="'+xa.x+'" y="'+(y0+15)+'" text-anchor="'+xa.a+'">'+esc(sl.x)+'</text>';
  if(o.two&&sl.d&&sl.d!==lastD)s+='<text class="ax" x="'+xa.x+'" y="'+(y0+29)+'" text-anchor="'+xa.a+'">'+esc(sl.d)+'</text>';
  if(sl.d)lastD=sl.d}
 s+='</svg>';
 host.style.height=H+'px';host.innerHTML=s;
 c.geo={padL:padL,sw:sw,n:n,y0:y0,tops:tops,mark:mark}}

/* ---------- İpucu kutusu: fareyle üzerine gelince, dokunmatikte dokununca ---------- */
function clearOn(){var on=document.querySelectorAll('.chart .on');for(var i=0;i<on.length;i++)on[i].classList.remove('on')}
function hideTip(){clearOn();TIP.id=null;TIP.i=-1;var t=$('tip');if(t)t.hidden=true}
function showTip(id,i){
 var c=REG[id],host=$(id),tip=$('tip');if(!c||!c.geo||!host||!tip){hideTip();return}
 var g=c.geo;i=Math.max(0,Math.min(g.n-1,i));var sl=c.slots[i];
 clearOn();TIP.id=id;TIP.i=i;
 var band=$(id+'-band');if(band){var bwid=Math.max(6,g.sw);band.setAttribute('x',r2(g.padL+(i+.5)*g.sw-bwid/2));band.setAttribute('width',r2(bwid));band.classList.add('on')}
 var bar=host.querySelector('[data-i="'+i+'"]');if(bar)bar.classList.add('on');
 set('tipV',sl.v==null?'Kayıt yok':(c.opts.tipVal||fmt)(sl.v));set('tipL',sl.t||'');
 tip.hidden=false;
 var rc=host.getBoundingClientRect(),tw=tip.offsetWidth,th=tip.offsetHeight,vw=document.documentElement.clientWidth;
 var left=Math.max(8,Math.min(vw-tw-8,rc.left+g.padL+(i+.5)*g.sw-tw/2)),top=rc.top-th+14;
 if(top<4)top=rc.top+g.y0+8;
 tip.style.left=Math.round(left+window.pageXOffset)+'px';tip.style.top=Math.round(top+window.pageYOffset)+'px'}
function chartOf(node){var h=node&&node.closest?node.closest('.chart'):null;return h&&REG[h.id]&&REG[h.id].geo?h:null}
function slotAt(host,clientX){var g=REG[host.id].geo;return Math.floor((clientX-host.getBoundingClientRect().left-g.padL)/g.sw)}
document.addEventListener('click',function(e){var h=chartOf(e.target);if(h)showTip(h.id,slotAt(h,e.clientX));else hideTip()});
document.addEventListener('pointermove',function(e){if(e.pointerType!=='mouse')return;var h=chartOf(e.target);
 if(h){var i=Math.max(0,Math.min(REG[h.id].geo.n-1,slotAt(h,e.clientX)));if(TIP.id!==h.id||TIP.i!==i)showTip(h.id,i)}else if(TIP.id)hideTip()});
document.addEventListener('keydown',function(e){
 if(e.key==='Escape'){hideTip();return}
 var h=chartOf(document.activeElement);if(!h)return;
 var g=REG[h.id].geo,fresh=TIP.id!==h.id,i=fresh?(g.mark>=0?g.mark:g.n-1):TIP.i;
 if(e.key==='ArrowLeft'){if(!fresh)i--}else if(e.key==='ArrowRight'){if(!fresh)i++}else if(e.key!=='Enter'&&e.key!==' ')return;
 e.preventDefault();showTip(h.id,i)});
document.addEventListener('focusout',function(e){if(e.target&&e.target.classList&&e.target.classList.contains('chart'))hideTip()});
var resizeTimer=0;
window.addEventListener('resize',function(){clearTimeout(resizeTimer);resizeTimer=setTimeout(function(){hideTip();for(var id in REG)draw(id)},120)});

/* ---------- Çubuklu liste ---------- */
function barList(id,list,name,value,unit,emptyText){
 var el=$(id);if(!el)return;
 if(!list.length){el.innerHTML='<div class="none">'+esc(emptyText||'Henüz yok')+'</div>';return}
 var mx=0,tot=0;list.forEach(function(r){var v=num(value(r));tot+=v;if(v>mx)mx=v});
 el.innerHTML=list.map(function(r){var v=num(value(r)),w=mx>0?Math.max(1.5,v/mx*100):0;
  return '<div class="row"><div class="rt"><span>'+name(r)+'</span><b>'+fmt(v)+(unit?' '+unit:'')+'</b><i>%'+(tot>0?Math.round(v/tot*100):0)+'</i></div><div class="track"><span style="width:'+w.toFixed(1)+'%"></span></div></div>'}).join('')}

/* ---------- Bölümler ---------- */
function hourSlot(t,v){var d=D(t),h=d.getHours(),s={v:v,t:dShort(t)+', '+hm(t)+'–'+hm(t+3600)};
 if(h%6===0){s.x=hm(t);s.lv=h===0?1:h%12===0?2:3;s.d=dShort(t)}return s}
function people(v){return fmt(v)+' kişi'}
function installs(v){return fmt(v)+' kurulum'}

function renderLive(p){
 set('now',fmt(p.now));
 var plats=arr(p.byPlatform);
 $('nowPlat').innerHTML=plats.length?plats.map(function(x){return '<span class="chip">'+platName(x.platform)+' · '+fmt(x.n)+'</span>'}).join(''):'<span class="chip">Şu an kimse oynamıyor</span>';
 var games=arr(p.games);
 $('games').innerHTML=games.length?games.map(function(g){return '<div><span>'+esc(g.name||g.game||'Oyun bilinmiyor')+'</span><b>'+fmt(g.n)+'</b></div>'}).join(''):'<div><span>Şu an oynanan oyun yok</span></div>';
 var pk=p.peak;
 if(!pk||typeof pk!=='object'){set('pkToday','–');set('pkWeek','–');set('pkAll','–');set('pkWhen','Geçmiş kaydı henüz yok.');set('pkSince','');return}
 set('pkToday',fmt(pk.today));set('pkWeek',fmt(pk.week));set('pkAll',fmt(pk.allTime));
 if(pk.allTimeHour==null&&pk.since==null){set('pkWhen','Geçmiş kaydı henüz başlamadı; şimdilik şu anki sayı gösteriliyor.');set('pkSince','');return}
 set('pkWhen',pk.allTimeHour!=null&&num(pk.allTime)>0?'Rekor: '+dLong(num(pk.allTimeHour))+', '+hm(num(pk.allTimeHour))+'–'+hm(num(pk.allTimeHour)+3600)+' arası':'');
 set('pkSince',pk.since!=null?sinceText(num(pk.since)):'')}

function renderHours(p,now){
 var list=arr(p.hourly),base=Math.floor(now/3600)*3600,map={},first=null,last=null,count=0,slots=[],i;
 list.forEach(function(r){if(!r||r.hour==null)return;var h=num(r.hour);map[h]=num(r.peak);if(first==null||h<first)first=h;if(last==null||h>last)last=h});
 for(i=47;i>=0;i--){var t=base-i*3600,v=null;
  if(map[t]!=null){v=map[t];count++}else if(first!=null&&t>first&&t<last)v=0;
  slots.push(hourSlot(t,v))}
 if(!count){placeholder('cHours',EARLY);set('cHoursNote','');return}
 chart('cHours',slots,{title:'Aynı anda oynayan, son 48 saat',h:190,ticks:4,two:true,mark:'max',tipVal:people,markVal:fmt});
 set('cHoursNote',count<6?EARLY:'')}

function renderDaily(p){
 var list=arr(p.daily),n=list.length;
 [['cActive','vActive','active','Günlük açan, son 14 gün',installs],['cPlayed','vPlayed','played','Günlük oynayan, son 14 gün',installs],
  ['cFresh','vFresh','fresh','Yeni kurulum, son 14 gün',installs],['cPeak','vPeak','peak','Günün en yükseği, son 14 gün',people]].forEach(function(def){
  var known=0,slots=list.map(function(r,i){r=obj(r);var t=num(r.day)+43200,v=r[def[2]]==null?null:num(r[def[2]]);if(v!=null)known++;
   var s={v:v,t:dLong(t)};if(i===0||((n-1-i)%4===0&&i>2)){s.x=dShort(t);s.lv=i===0||i===n-1?1:2}return s});
  var now=n?slots[n-1].v:null,head=$(def[1]);
  if(head)head.innerHTML=now==null?'':fmt(now)+'<small>bugün</small>';
  if(!known){placeholder(def[0],EARLY);set(def[0]+'Note','');return}
  chart(def[0],slots,{title:def[3],h:132,ticks:2,mark:'last',label:false,tipVal:def[4]});
  set(def[0]+'Note',known<3?EARLY:known<n?'Boş günlerde henüz kayıt tutulmuyordu.':'')})}

function renderInstalls(p,dl){
 set('inst',fmt(p.installs));set('instNew','Bugün yeni: '+fmt(p.newToday));set('a24',fmt(p.active24h));
 set('dl',dl?fmt(dl.total):'–');
 set('dlBy',dl?'Mac '+fmt(dl.mac)+' · Windows '+fmt(dl.windows)+' · Android '+fmt(dl.android)+' · TV '+fmt(dl.tv):'GitHub sayıları şu an alınamadı');
 set('latest',dl&&dl.latest||'–');
 barList('plat',arr(p.installsByPlatform),function(r){return platName(r.platform)},function(r){return r.n});
 var latest=String(dl&&dl.latest||'');if(latest.charAt(0)==='v'||latest.charAt(0)==='V')latest=latest.slice(1);
 var vers=arr(p.versions),onLatest=null;
 vers.forEach(function(r){if(latest&&String(r.app)===latest)onLatest=num(r.n)});
 barList('vers',vers,function(r){return esc(r.app)+(latest&&String(r.app)===latest?'<em>en yeni</em>':'')},function(r){return r.n},'','Henüz sürüm bilgisi yok');
 set('verNote',onLatest!=null?'En yeni sürümü ('+latest+') kullanan: '+fmt(onLatest)+' kurulum':'Son 7 günde açılan kurulumların sürümü');
 barList('ulangs',arr(p.langs),function(r){return langName(r.lang)},function(r){return r.n},'','Henüz dil bilgisi yok');
 barList('dlList',dl?[['Mac',dl.mac],['Windows',dl.windows],['Android',dl.android],['TV',dl.tv]]:[],function(r){return r[0]},function(r){return r[1]},'','GitHub sayıları şu an alınamadı')}

function renderTranslations(t,pool,now){
 set('lines',fmt(t.lines));set('words',fmt(t.words)+' kelime · bugün '+fmt(t.today)+' satır');
 set('rev',fmt(t.reviewed));set('today','Bugün '+fmt(t.today)+' satır, '+fmt(t.wordsToday)+' kelime çevrildi');
 set('pool',fmt(pool.lines));set('poolSeen',fmt(pool.seen)+' kez görüldü');
 barList('langs',arr(t.byLang),function(r){return langName(r.lang)},function(r){return r.n},'satır');
 var base=Math.floor(now/3600)*3600,map={},slots=[];
 arr(t.hourly).forEach(function(h){if(h&&h.hour!=null)map[num(h.hour)]=num(h.n)});
 for(var i=23;i>=0;i--){var ts=base-i*3600;slots.push(hourSlot(ts,map[ts]||0))}
 chart('cTr',slots,{title:'Saatlik çeviri, son 24 saat',h:200,ticks:3,two:true,mark:'max',tipVal:function(v){return fmt(v)+' satır'},markVal:fmt})}

function renderSpend(s,now){
 var spent=num(s.translateToday),cap=num(s.translateCap),part=cap>0?spent/cap:0;
 set('spend',usd(spent));
 $('spendBar').style.width=Math.min(100,part*100).toFixed(1)+'%';
 $('spendMeter').className='meter'+(part>=1?' bad':part>=.8?' warn':'');
 var capEl=$('spendCap');capEl.textContent='Günlük sınır: '+usd(cap)+' · kullanılan: %'+Math.round(part*100);
 if(part>=.8){var f=document.createElement('span');f.className='flag '+(part>=1?'bad':'warn');f.textContent=part>=1?' · Sınıra ulaşıldı':' · Sınıra yaklaşıyor';capEl.appendChild(f)}
 set('spendAsk',"Nino'ya Sor harcaması: "+usd(s.assistantToday));
 var map={},slots=[],sum=0;
 arr(s.week).forEach(function(c){if(c&&c.day!=null)map[String(c.day)]=num(c.usd)});
 for(var i=6;i>=0;i--){var d=new Date((now-i*86400)*1000),k=d.toISOString().slice(0,10),v=map[k]||0;sum+=v;
  slots.push({v:v,t:d.toLocaleDateString('tr-TR',{day:'numeric',month:'long',weekday:'long',timeZone:'UTC'}),x:d.toLocaleDateString('tr-TR',{weekday:'short',timeZone:'UTC'}),lv:1})}
 set('weekSum','7 günde toplam '+usd(sum));
 chart('cWeek',slots,{title:'Çeviri harcaması, son 7 gün',h:170,ticks:3,dec:true,mark:'last',ref:cap>0?cap:0,refLabel:cap>0?'Günlük sınır '+usd(cap):'',tipVal:usd,
  tick:function(v){return '$'+num(v).toLocaleString('tr-TR',{maximumFractionDigits:2})}})}

function renderSupport(d,s){
 var rep=obj(d.reports);set('rep',fmt(rep.total));set('repNew','Okunmamış: '+fmt(rep.fresh));
 var a=obj(d.assistant);set('ask',fmt(a.questionsToday)+' soru');set('askCost','Harcama '+usd(s.assistantToday));
 set('askMix','Hazır cevap: %'+Math.round(num(a.readyRate)*100)+' ('+fmt(num(a.library))+' kütüphane, '+fmt(num(a.cache))+' kayıtlı'+(num(a.busyLibrary)?', '+fmt(num(a.busyLibrary))+' yoğunken':'')+')');
 set('askModels','Model çağrısı: '+fmt(num(a.primary))+' ana'+(a.primaryModel?' ('+a.primaryModel+')':'')+' · '+fmt(num(a.fallback))+' yedek'+(a.fallbackModel?' ('+a.fallbackModel+')':'')+(num(a.busy)?' · '+fmt(num(a.busy))+' "yoğunum"':''));
 set('askSpend','Ana: '+usd(num(a.primaryUsd))+' / '+usd(num(a.primaryCapUsd))+' (sayılan) · Yedek: '+usd(num(a.fallbackUsd))+' / '+usd(num(a.fallbackCapUsd))+' (gerçek)')}

function renderTvs(t){
 var EMPTY='TV uygulamasının yeni sürümü (V3.5) kuruldukça burada görünecek';
 var count={androidtv:0,samsung:0,lg:0},models={androidtv:[],samsung:[],lg:[]};
 arr(t.byBrand).forEach(function(r){if(count[r.brand]!=null)count[r.brand]=num(r.n)});
 arr(t.models).forEach(function(r){if(models[r.brand]&&models[r.brand].length<20)models[r.brand].push(r)});
 set('tvTotal',fmt(t.total));set('tvA',fmt(count.androidtv));set('tvS',fmt(count.samsung));set('tvL',fmt(count.lg));
 [['tvModelsA','androidtv'],['tvModelsS','samsung'],['tvModelsL','lg']].forEach(function(d){
  barList(d[0],models[d[1]],function(r){return esc(r.model)},function(r){return r.n},'',count[d[1]]?'Model bilgisi yok':EMPTY)});
 barList('tvVers',arr(t.versions),function(r){return esc(r.app)},function(r){return r.n},'',EMPTY)}

function part(fn){try{fn()}catch(e){if(window.console)console.error(e)}}
function render(d){
 d=obj(d);var now=num(d.now)||Math.floor(Date.now()/1000),p=obj(d.players),s=obj(d.spend),open=TIP.id,openI=TIP.i;
 part(function(){renderLive(p)});
 part(function(){renderHours(p,now)});
 part(function(){renderDaily(p)});
 part(function(){renderInstalls(p,d.downloads&&typeof d.downloads==='object'?d.downloads:null)});
 part(function(){renderTvs(obj(d.tvs))});
 part(function(){renderTranslations(obj(d.translations),obj(d.pool),now)});
 part(function(){renderSpend(s,now)});
 part(function(){renderSupport(d,s)});
 status('Canlı · son yenileme '+D(now).toLocaleTimeString('tr-TR'),false);
 if(open&&REG[open])showTip(open,openI)}

/* ---------- Sağlık (ölçüm) ---------- */
var HDAYS=7,hLast=0;
var KINDS={crash:'Çökme',error:'Hata',ps5_connect:'PS5 bağlanamadı',ps5_drop:'PS5 koptu',tv_connect:'TV bağlanamadı',tv_drop:'TV koptu'};
var METRICS={'tr.total':'Gecikme (okuma → ekranda çeviri)',ocr:'Yazı tanıma (kare)','tr.cache':'Çeviri: önbellek','tr.pack':'Çeviri: oyun paketi','tr.pool':'Çeviri: Nino havuzu','tr.provider':'Çeviri: çevirmen',first_frame:'PS5 bağlantısı → ilk kare',first_subtitle:'Oturum → ilk çeviri','ps5.connect':'PS5 bağlanma','tv.connect':'TV bağlanma',launch:'Uygulama açılışı',session:'Oturum süresi','ps5.after':'PS5 kopmadan önce','tv.after':'TV kopmadan önce'};
var VIAS={lan:'Ev ağı',remote:'İnternet üzerinden',xbox:'Xbox'};
var BRANDS={androidtv:'Android TV / Google TV',samsung:'Samsung',lg:'LG'};
NAMES.androidtv='Android TV';NAMES.webos='LG webOS';NAMES.tizen='Samsung Tizen';
function pct(v){return v==null?'–':'%'+(Math.round(num(v)*1000)/10).toLocaleString('tr-TR')}
function dur(v,unit){if(v==null)return '–';v=num(v);if(unit==='s'){if(v<60)return fmt(v)+' sn';if(v<3600)return fmt(Math.round(v/60))+' dk';return (Math.round(v/360)/10).toLocaleString('tr-TR')+' sa'}
 if(v<1000)return fmt(v)+' ms';return (Math.round(v/100)/10).toLocaleString('tr-TR')+' sn'}
function metricName(m){m=String(m||'');var i=m.indexOf(':');if(i>0)return esc((METRICS[m.slice(0,i)]||m.slice(0,i))+' · '+m.slice(i+1));return esc(METRICS[m]||m)}
function cls(v,warn,bad,low){if(v==null)return '';return low?(v<bad?'bad':v<warn?'warn':''):(v>bad?'bad':v>warn?'warn':'')}
function table(id,head,rows,empty){var el=$(id);if(!el)return;
 if(!rows.length){el.innerHTML='<div class="none">'+esc(empty||'Henüz kayıt yok')+'</div>';return}
 el.innerHTML='<table class="tbl"><thead><tr>'+head.map(function(h){return '<th scope="col">'+esc(h)+'</th>'}).join('')+'</tr></thead><tbody>'+
  rows.map(function(r){return '<tr>'+r.map(function(c){c=obj(c);return '<td'+(c.c?' class="'+c.c+'"':'')+'>'+(c.h!=null?c.h:esc(c.t))+'</td>'}).join('')+'</tr>'}).join('')+'</tbody></table>'}
function okFail(ok,fail){var t=num(ok)+num(fail);return t?pct(num(ok)/t)+' <small>('+fmt(t)+')</small>':'–'}

function renderHealth(h){
 h=obj(h);
 if(!h.ready){set('hNote','Ölçüm tabloları henüz kurulmadı (sunucuda 0016 migration gerekiyor).');return}
 var t=obj(h.totals);
 set('hNote',num(t.launches)+num(t.sessions)?'':'Yeni uygulamalar ölçüm gönderdikçe burada görünecek.');
 set('hCrashFree',pct(t.crashFree));set('hCrashes',fmt(t.crashes)+' çökme · '+fmt(t.launches)+' açılış');
 set('hErr',t.errorsPer100==null?'–':(Math.round(num(t.errorsPer100)*10)/10).toLocaleString('tr-TR'));set('hErrN',fmt(t.errors)+' hata · '+fmt(t.sessions)+' oturum');
 set('hPs5',pct(t.ps5Rate));set('hPs5N',fmt(t.ps5Ok)+' başarılı · '+fmt(t.ps5Fail)+' başarısız · '+fmt(t.ps5Drops)+' kopma');
 set('hTv',pct(t.tvRate));set('hTvN',fmt(t.tvOk)+' başarılı · '+fmt(t.tvFail)+' başarısız · '+fmt(t.tvDrops)+' kopma');
 var tim=arr(h.timings),lat=null;tim.forEach(function(r){if(r.metric==='tr.total'&&r.platform==='*')lat=r});
 set('hLat',lat?dur(lat.p50):'–');set('hLatN',lat?'p90 '+dur(lat.p90)+' · p99 '+dur(lat.p99)+' · '+fmt(lat.n)+' satır':'Ortanca (p50)');

 var daily=arr(h.daily),n=daily.length,known=0;
 var slots=daily.map(function(r,i){r=obj(r);var v=r.errorsPer100==null?null:Math.round(num(r.errorsPer100)*10)/10;if(v!=null)known++;var tm=num(r.day)+43200;
  var s={v:v,t:dLong(tm)+' · '+fmt(r.errors)+' hata, '+fmt(r.sessions)+' oturum, '+fmt(r.crashes)+' çökme'};
  if(n<=8||i===0||i===n-1||(n-1-i)%7===0){s.x=dShort(tm);s.lv=i===0||i===n-1?1:2}return s});
 if(!known)placeholder('cHealth',EARLY);
 else chart('cHealth',slots,{title:'Günlük hata, 100 oturumda',h:170,ticks:3,dec:true,mark:'last',tipVal:function(v){return v.toLocaleString('tr-TR')+' / 100 oturum'}});

 barList('hProblems',arr(h.problems).slice(0,12),function(p){var pl=Object.keys(obj(p.platforms)).map(function(k){return NAMES[k]||k}).join(', ');
  return esc(KINDS[p.kind]||p.kind)+' · <code>'+esc(p.code)+'</code><em>'+esc(pl)+'</em>'},function(p){return p.n},'','Sorun kaydı yok');

 table('hVersions',['Platform · sürüm','Açılış','Oturum','Çökmesiz','Hata/100','PS5','TV'],arr(h.versions).map(function(v){
  return [{h:platName(v.platform)+' <small>'+esc(v.app||'?')+'</small>'},{t:fmt(v.launches)},{t:fmt(v.sessions)},
   {t:pct(v.crashFree),c:cls(v.crashFree,.995,.98,true)},{t:v.errorsPer100==null?'–':(Math.round(num(v.errorsPer100)*10)/10).toLocaleString('tr-TR'),c:cls(v.errorsPer100,20,100)},
   {h:okFail(v.ps5Ok,v.ps5Fail),c:cls(v.ps5Rate,.9,.75,true)},{h:okFail(v.tvOk,v.tvFail),c:cls(v.tvRate,.9,.75,true)}]}),'Henüz ölçüm gelmedi');

 var ORDER=['tr.total','ocr','tr.cache','tr.pack','tr.pool','tr.provider','first_subtitle','first_frame','ps5.connect','tv.connect','launch','session','ps5.after','tv.after'];
 function rank(m){var i=ORDER.indexOf(String(m).split(':')[0]);return i<0?ORDER.length:i}
 var all=tim.filter(function(r){return r.platform==='*'}).sort(function(a,b){return rank(a.metric)-rank(b.metric)||(a.metric<b.metric?-1:1)});
 table('hTimings',['Ölçüm','Adet','p50','p90','p99','En uzun'],all.map(function(r){
  return [{h:metricName(r.metric)},{t:fmt(r.n)},{t:dur(r.p50,r.unit)},{t:dur(r.p90,r.unit)},{t:dur(r.p99,r.unit)},{t:dur(r.max,r.unit)}]}),'Henüz süre ölçümü yok');
 var byPlat=tim.filter(function(r){return r.metric==='tr.total'&&r.platform!=='*'});
 table('hLatency',['Platform','Satır','p50','p90','p99'],byPlat.map(function(r){
  return [{h:platName(r.platform)},{t:fmt(r.n)},{t:dur(r.p50)},{t:dur(r.p90),c:cls(r.p90,1500,3000)},{t:dur(r.p99)}]}),'Henüz gecikme ölçümü yok');

 function rateRow(name){return function(r){return name(r.key)+'<em>'+pct(r.rate)+'</em>'}}
 barList('hTvBrands',arr(h.tvBrands),rateRow(function(k){return esc(BRANDS[k]||k)}),function(r){return num(r.ok)+num(r.fail)},'deneme','Henüz TV bağlantısı yok');
 barList('hVia',arr(h.ps5Via),rateRow(function(k){return esc(VIAS[k]||k)}),function(r){return num(r.ok)+num(r.fail)},'deneme','Henüz PS5 bağlantısı yok');
 barList('hGames',arr(h.games),function(g){return esc(g.name||g.game||'Oyun bilinmiyor')+'<em>'+fmt(g.minutes)+' dk</em>'},function(g){return g.sessions},'oturum','Henüz oyun yok');

 var rec=arr(h.recent);
 $('hRecent').innerHTML=rec.length?rec.map(function(r){r=obj(r);
  return '<div class="rec"><time>'+esc(dShort(num(r.at))+' '+hm(num(r.at)))+'</time><span>'+esc(KINDS[r.kind]||r.kind)+' · <code>'+esc(r.code)+'</code>'+
   (r.detail?' <small>'+esc(r.detail)+'</small>':'')+'<small>'+platName(r.platform)+' '+esc(r.app)+(r.os?' · '+esc(r.os):'')+(r.device?' · '+esc(r.device):'')+'</small></span></div>'}).join(''):'<div class="none">Kayıt yok</div>'}

/* ---------- TV bağlantıları ---------- */
var REASONS={timeout:'Zaman aşımı (sessizlik)',write_error:'Gönderilemedi (yazma hatası)',closed:'Karşı taraf kapattı',resume:'Uygulama öne geldi',network_change:'Ağ değişti',network_lost:'Ağ gitti',replaced:'Yerine yeni bağlantı geldi',other:'Diğer'};
function tvName(b,m){return esc(BRANDS[b]||b||'Marka yok')+(m?' <small>'+esc(m)+'</small>':' <small>model bilinmiyor</small>')}
function renderTvLinks(t){
 if(!t){set('tlNote','TV bağlantı tabloları henüz kurulmadı (sunucuda 0018 migration gerekiyor).');return}
 var tot=obj(t.totals);
 set('tlNote',num(tot.ok)+num(tot.drops)+num(tot.fails)?'':'TV bağlantısı bildiren uygulamalar geldikçe burada görünecek.');
 set('tlRate',pct(tot.dropRate));set('tlRateN',fmt(tot.drops)+' kopma · '+fmt(tot.ok)+' bağlantı');
 set('tlAfter',dur(tot.avgAfter,'s'));
 var l24=arr(t.last24),d24=0;l24.forEach(function(r){d24+=num(r.drops)});set('tl24',fmt(d24));set('tl24N',fmt(l24.length)+' model');
 var al=arr(t.alerts);set('tlAlertN',fmt(al.length));
 $('tlAlerts').innerHTML=al.length?al.map(function(a){a=obj(a);
  return '<div class="rec"><time>'+esc(hm(num(a.last)))+'</time><span><b class="flag warn">'+fmt(a.hour)+' kopma / 1 sa · '+fmt(a.sixHours)+' / 6 sa</b> · '+tvName(a.brand,a.model)+
   '<small>'+platName(a.platform)+(a.tvApp?' · TV uygulaması '+esc(a.tvApp):'')+' · nedenler: '+arr(a.codes).map(function(c){return esc(REASONS[c]||c)}).join(', ')+' · #'+esc(a.id)+'</small></span></div>'}).join(''):'<div class="none">Uyarı yok</div>';
 function row(name){return function(r){return [{h:name(r)},{t:fmt(num(r.ok)+num(r.fails))},{t:fmt(r.drops)},{t:pct(r.dropRate),c:cls(r.dropRate,.2,.5)},{t:dur(r.avgAfter,'s')},{t:pct(r.connectRate),c:cls(r.connectRate,.9,.75,true)}]}}
 var head=['','Deneme','Kopma','Kopma oranı','Bağlı kalma','Bağlanma'];
 table('tlModels',['Marka · model'].concat(head.slice(1)),arr(t.models).map(row(function(r){return tvName(r.brand,r.model)})),'Henüz TV bağlantısı yok');
 table('tlLast24',['Model','Kopma','Bağlantı','Kurulum'],l24.map(function(r){return [{h:tvName(r.brand,r.model)},{t:fmt(r.drops),c:'warn'},{t:fmt(r.ok)},{t:fmt(r.installs)}]}),'Son 24 saatte kopma yok');
 barList('tlReasons',arr(t.reasons),function(r){return esc(REASONS[r.code]||r.code)+'<em>ort. '+dur(r.avgAfter,'s')+'</em>'},function(r){return r.drops},'kopma','Kopma yok');
 table('tlApps',['TV uygulaması'].concat(head.slice(1)),arr(t.tvApps).map(row(function(r){return esc(BRANDS[r.brand]||r.brand||'?')+' <small>'+esc(r.tvApp||'sürüm bilinmiyor')+'</small>'})),'Henüz yok');
 table('tlSenders',['Platform'].concat(head.slice(1)),arr(t.senders).map(row(function(r){return platName(r.platform)})),'Henüz yok')}

/* ---------- Otomatik teşhis ---------- */
function renderDiag(g){
 if(!g){set('dgNote','Teşhis tabloları henüz kurulmadı (sunucuda 0019 migration gerekiyor).');return}
 set('dgNote',num(g.total)?'':'Uygulamaların bekçisi sorun bildirdikçe burada görünecek.');
 set('dgTotal',fmt(g.total));set('dgFreshN',fmt(arr(g.fresh).length));set('dgRegN',fmt(arr(g.regressions).length));
 function name(x){return esc(x.title)+'<em>'+platName(x.platform)+'</em>'+(x.model?'<em>'+esc(x.model)+'</em>':'')+'<small style="display:block;color:var(--soft);font-size:12px">'+esc(x.text)+(x.installs?' · '+fmt(x.installs)+' kurulum (3 gün)':'')+(x.summary?' · '+esc(x.summary):'')+'</small>'}
 barList('dgTop',arr(g.top).slice(0,12),name,function(x){return x.n},'','Otomatik bildirim yok');
 barList('dgFresh',arr(g.fresh),function(x){return name(x)+'<small style="display:block;color:var(--soft);font-size:12px">İlk: '+esc(dShort(num(x.firstSeen))+' '+hm(num(x.firstSeen)))+' · '+esc(x.firstApp)+'</small>'},function(x){return x.n},'','Yeni sorun yok');
 table('dgReg',['Platform · sorun','Yeni sürüm','Önceki','Artış'],arr(g.regressions).map(function(r){
  return [{h:platName(r.platform)+' <small>'+esc(r.title)+'</small>'},{h:esc(r.newApp)+' <small>'+fmt(r.nNew)+' bildirim · %'+(Math.round(num(r.rateNew)*1000)/10).toLocaleString('tr-TR')+'</small>'},
   {h:esc(r.oldApp)+' <small>'+fmt(r.nOld)+' bildirim · %'+(Math.round(num(r.rateOld)*1000)/10).toLocaleString('tr-TR')+'</small>'},{t:r.factor==null?'yeni':(Math.round(num(r.factor)*10)/10).toLocaleString('tr-TR')+'×',c:'bad'}]}),'Artış yok')}

async function loadHealth(){
 if(!key)return;hLast=Date.now();
 var r=null;try{r=await fetch('/v1/events/stats?days='+HDAYS,{headers:{authorization:'Bearer '+key}})}catch(e){r=null}
 if(!r||!r.ok){set('hNote','Sağlık verisi alınamadı'+(r?' ('+r.status+')':'')+'; dakikada bir yeniden denenir.');return}
 var d=null;try{d=await r.json()}catch(e){d=null}
 part(function(){renderHealth(d)});part(function(){if(d&&d.ready)renderTvLinks(d.tvLinks)});part(function(){if(d&&d.ready)renderDiag(d.diag)})}
Array.prototype.forEach.call(document.querySelectorAll('.seg button'),function(b){b.onclick=function(){
 HDAYS=num(b.getAttribute('data-days'))||7;
 Array.prototype.forEach.call(document.querySelectorAll('.seg button'),function(x){x.setAttribute('aria-pressed',x===b?'true':'false')});
 loadHealth()}});

async function load(){
 if(!key){gate(true,'');return}
 var r=null;try{r=await fetch('/v1/stats',{headers:{authorization:'Bearer '+key}})}catch(e){r=null}
 var first=$('app').hidden;
 if(!r){if(first)gate(true,'Sunucuya ulaşılamadı. Bağlantını kontrol edip yeniden dene.');else status('Bağlantı kesildi; yeniden deneniyor',true);return}
 if(r.status===401){gate(true,'Anahtar kabul edilmedi.');return}
 var d=null;if(r.ok){try{d=await r.json()}catch(e){d=null}}
 if(!d){if(first)gate(true,'Sunucu şu an yanıt vermiyor ('+r.status+'). Biraz sonra yeniden dene.');else status('Sunucu yanıt vermedi; yeniden deneniyor',true);return}
 gate(false);render(d);if(Date.now()-hLast>60000)loadHealth()}
load();setInterval(load,15000);
</script></body></html>`;
