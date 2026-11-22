// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// OBS "Tarayıcı kaynağı" sayfası (`GET /obs`). Kendi içinden `/events?viewer=obs`'ye bağlanır.
///
/// Sorgu: `size` (1080p'de piksel yazı boyu, varsayılan 46), `bottom` (alttan %, varsayılan 7),
/// `bg` (sayı: kutu koyuluğu 0–100, varsayılan 70; ya da `green` / `black` / `magenta`: bütün sayfanın
/// zemini, chroma key için). Metin yalnız düz yazı olarak konur (HTML yorumlanmaz).
public enum LegacyOBSPage {
    public static let html = #"""
<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nino OBS</title>
<style>
  html, body { margin: 0; height: 100%; overflow: hidden; background: transparent; }
  body { font-family: -apple-system, system-ui, "Segoe UI", Roboto, sans-serif; }
  #wrap { position: absolute; left: 0; right: 0; display: flex; justify-content: center; pointer-events: none; }
  #line { max-width: 86vw; text-align: center; white-space: pre-line; color: #fff; line-height: 1.25;
          padding: .18em .55em; border-radius: .28em; opacity: 0; transition: opacity .18s ease; }
  #line.on { opacity: 1; }
  #line.band { max-width: none; width: 100vw; border-radius: 0; }
  body.key #line { text-shadow: 0 0 .12em #000, 0 0 .12em #000, 0 .05em .2em #000; }
</style>
</head>
<body>
<div id="wrap"><div id="line"></div></div>
<script>
(function () {
  var q = new URLSearchParams(location.search);
  var size = parseFloat(q.get('size')) || 46;
  var bottom = q.has('bottom') ? parseFloat(q.get('bottom')) : 7;
  var bg = (q.get('bg') || '70').toLowerCase();
  var keys = { green: '#00ff00', black: '#000000', magenta: '#ff00ff' };
  var line = document.getElementById('line');
  var wrap = document.getElementById('wrap');
  var fonts = {
    system: '-apple-system, system-ui, "Segoe UI", Roboto, sans-serif',
    modern: '"Helvetica Neue", Inter, "Segoe UI", Roboto, sans-serif',
    condensed: '"Avenir Next Condensed", "Arial Narrow", "Roboto Condensed", sans-serif',
    rounded: 'ui-rounded, "SF Pro Rounded", "Nunito", sans-serif'
  };
  var timer = null;

  if (keys[bg]) {
    document.body.style.background = keys[bg];
    document.body.className = 'key';
    line.style.background = 'transparent';
  } else {
    var dark = Math.max(0, Math.min(100, parseFloat(bg) || 0)) / 100;
    line.style.background = 'rgba(0,0,0,' + dark + ')';
  }

  function layout() {
    line.style.fontSize = (size * window.innerHeight / 1080) + 'px';
    wrap.style.bottom = bottom + '%';
  }
  window.addEventListener('resize', layout);
  layout();

  function hide() {
    if (timer) { clearTimeout(timer); timer = null; }
    line.className = line.className.replace(/\bon\b/g, '').trim();
  }

  function parse(e) { try { return JSON.parse(e.data) || {}; } catch (x) { return {}; } }

  function connect() {
    var es = new EventSource('/events?viewer=obs');
    es.addEventListener('subtitle', function (e) {
      var d = parse(e);
      if (typeof d.text !== 'string' || !d.text) return hide();
      line.textContent = d.text;
      if (!/\bon\b/.test(line.className)) line.className = (line.className + ' on').trim();
      if (timer) clearTimeout(timer);
      timer = setTimeout(hide, d.duration > 0 ? d.duration : 15000);
    });
    es.addEventListener('clear', hide);
    es.addEventListener('stopped', hide);
    es.addEventListener('style', function (e) {
      var s = parse(e);
      line.style.fontWeight = s.bold ? '700' : '500';
      line.style.color = s.textColor === 'yellow' ? '#ffd60a' : '#ffffff';
      if (fonts[s.font]) line.style.fontFamily = fonts[s.font];
      if (s.backgroundShape === 'band') line.classList.add('band'); else line.classList.remove('band');
      if (!q.has('size') && s.fontSize > 0) { size = s.fontSize; layout(); }
      if (!q.has('bottom') && s.bottomPercent >= 0) { bottom = s.bottomPercent; layout(); }
    });
    es.onerror = function () {
      if (es.readyState === 2) { setTimeout(connect, 2000); }
    };
  }
  connect();
})();
</script>
</body>
</html>
"""#
}
