// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Kaynak kuralları (ES5, lisans başlığı, eski ad yok) ve iki paketin üretilip doğru yapıda olması.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const APP = path.join(__dirname, '..');

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    if (fs.statSync(p).isDirectory()) { if (!['dist', 'build', 'node_modules'].includes(name)) walk(p, out); }
    else out.push(p);
  }
  return out;
}

const pageScripts = [...walk(path.join(APP, 'src')), ...walk(path.join(APP, 'platform'))].filter((p) => p.endsWith('.js'));
const ownFiles = walk(APP).filter((p) => /\.(js|css|html|py|xml|md)$/.test(p));

test('TV sayfasındaki betikler ES5 (eski TV tarayıcıları)', () => {
  for (const file of pageScripts) {
    const code = fs.readFileSync(file, 'utf8').replace(/\/\/.*$/gm, '').replace(/'(?:[^'\\\n]|\\.)*'/g, "''");
    for (const [what, re] of [['ok işlevi', /=>/], ['let', /\blet\s/], ['const', /\bconst\s/], ['şablon yazı', /`/], ['class', /\bclass\s+\w/]]) {
      assert.ok(!re.test(code), path.relative(APP, file) + ': ' + what);
    }
  }
});

test('her dosyada AGPL başlığı ve Nino telif satırı', () => {
  for (const file of ownFiles) {
    const head = fs.readFileSync(file, 'utf8').split('\n').slice(0, 5).join('\n');
    assert.ok(head.includes('SPDX-License-Identifier: AGPL-3.0-only'), path.relative(APP, file));
    assert.ok(head.includes('Copyright (C) 2026 Nino contributors'), path.relative(APP, file));
  }
});

// Eski adın kendisi de bu dosyada yazılmasın diye parçalardan kurulur.
const OLD = new RegExp(['co', 'uch'].join(''), 'i');

test('eski proje adı geçmez', () => {
  for (const file of walk(APP).filter((p) => !/\.(png|ttf)$/.test(p) && !p.includes(path.sep + 'dist' + path.sep) && !p.includes(path.sep + 'build' + path.sep))) {
    assert.ok(!OLD.test(fs.readFileSync(file, 'utf8')), path.relative(APP, file));
  }
});

test('LG .ipk ve Samsung .wgt üretilir', () => {
  execFileSync('python3', [path.join(APP, 'tools', 'package.py')]);
  const version = /var VERSION = '([0-9.]+)'/.exec(fs.readFileSync(path.join(APP, 'src/js/main.js'), 'utf8'))[1];
  const ipk = path.join(APP, 'dist', `com.ninotranslator.tv_${version}_all.ipk`);
  const wgt = path.join(APP, 'dist', `nino-samsung_${version}.wgt`);
  const ar = fs.readFileSync(ipk);
  assert.strictEqual(ar.subarray(0, 8).toString(), '!<arch>\n');
  assert.strictEqual(ar.subarray(8, 24).toString().trim(), 'debian-binary');
  const zip = execFileSync('unzip', ['-l', wgt]).toString();
  for (const name of ['config.xml', 'index.html', 'platform.js', 'js/main.js', 'img/nino-bot.png']) assert.ok(zip.includes(name), name);
  const config = execFileSync('unzip', ['-p', wgt, 'config.xml']).toString();
  assert.ok(config.includes('id="NinoTVApps.Nino"'));
  assert.ok(config.includes(`version="${version}"`));
  const tizenPlatform = execFileSync('unzip', ['-p', wgt, 'platform.js']).toString();
  assert.ok(tizenPlatform.includes('backKey: 10009') && tizenPlatform.includes('ninoReportTv = function'));
  const appinfo = JSON.parse(fs.readFileSync(path.join(APP, 'build/webos/appinfo.json'), 'utf8'));
  assert.strictEqual(appinfo.id, 'com.ninotranslator.tv');
  assert.strictEqual(appinfo.version, version);
  assert.ok(fs.readFileSync(path.join(APP, 'build/webos/platform.js'), 'utf8').includes('backKey: 461'));
});

test('index.html\'deki her betik ve görsel iki pakette de var', () => {
  const html = fs.readFileSync(path.join(APP, 'src/index.html'), 'utf8');
  const refs = [...html.matchAll(/(?:src|href)="([^"$:]+)"/g)].map((m) => m[1]);
  assert.ok(refs.includes('js/diag.js') && refs.includes('js/telemetry.js'));
  for (const target of ['webos', 'tizen']) {
    for (const ref of refs) assert.ok(fs.existsSync(path.join(APP, 'build', target, ref)), target + ': ' + ref);
  }
});

test('göndericiye giden kimlik ölçüm kimliğinden ayrı anahtarda', () => {
  const main = fs.readFileSync(path.join(APP, 'src/js/main.js'), 'utf8');
  assert.match(main, /id: linkId,/);
  assert.match(main, /function linkId\(\) \{ return storedId\('nino\.linkId'\); \}/);
  assert.match(main, /function installId\(\) \{ return storedId\('ninoTvId'\); \}/);
});
