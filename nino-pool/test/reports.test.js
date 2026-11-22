// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";

const NOW = 1763300000;
const TOKEN = "deneme-anahtari";
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");

function setup() {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz" };
  const call = (path, { method = "GET", body, token } = {}) => handle(new Request(`http://pool${path}`, {
    method, body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
    headers: token ? { authorization: `Bearer ${token}` } : {},
  }), env, NOW);
  return { env, call };
}
const report = (extra = {}) => ({ v: 1, install: randomUUID(), app: "0.2.0", platform: "windows", language: "tr",
  text: "OBS'te iki altyazı çıkıyor", contact: "@niyazi", log: "günlük satırı", images: [{ mime: "image/png", data: png.toString("base64") }], ...extra });

test("bildirim fotoğrafıyla yazılır ve anahtarla okunur", async () => {
  const { call } = setup();
  const sent = await call("/v1/reports", { method: "POST", body: report() });
  assert.equal(sent.status, 200);
  const { id } = await sent.json();
  assert.equal((await call("/v1/reports")).status, 401);
  const list = await (await call("/v1/reports", { token: TOKEN })).json();
  assert.equal(list.reports.length, 1);
  assert.equal(list.reports[0].images, 1);
  assert.equal(list.reports[0].text, "OBS'te iki altyazı çıkıyor");
  const image = await call(`/v1/reports/${id}/images/0`, { token: TOKEN });
  assert.equal(image.headers.get("content-type"), "image/png");
  assert.deepEqual(Buffer.from(await image.arrayBuffer()), png);
  const full = await (await call(`/v1/reports/${id}`, { token: TOKEN })).json();
  assert.equal(full.report.log, "günlük satırı");
  assert.equal((await call(`/v1/reports/${id}/status`, { method: "POST", body: "done", token: TOKEN })).status, 200);
});

test("bozuk bildirim ve fazla fotoğraf reddedilir; kurulum başına günlük sınır", async () => {
  const { call } = setup();
  assert.equal((await call("/v1/reports", { method: "POST", body: report({ text: "" }) })).status, 400);
  assert.equal((await call("/v1/reports", { method: "POST", body: report({ platform: "dos" }) })).status, 400);
  const four = Array(4).fill({ mime: "image/png", data: png.toString("base64") });
  assert.equal((await call("/v1/reports", { method: "POST", body: report({ images: four }) })).status, 400);
  assert.equal((await call("/v1/reports", { method: "POST", body: report({ images: [{ mime: "text/html", data: "PGI+" }] }) })).status, 400);
  const install = randomUUID();
  for (let i = 0; i < 10; i++) assert.equal((await call("/v1/reports", { method: "POST", body: report({ install }) })).status, 200);
  assert.equal((await call("/v1/reports", { method: "POST", body: report({ install }) })).status, 429);
});

test("okuma sayfası veri içermez", async () => {
  const { call } = setup();
  const page = await call("/reports");
  assert.equal(page.status, 200);
  assert.match(await page.text(), /Nino Bildirimleri/);
});

test("cihaz bilgileri bildirimle saklanır; eski sürüm göndermezse boş kalır", async () => {
  const { call } = setup();
  const device = "app: 3.4.0 (19) | device: Mac16,1 | system: macOS 27.0 | tv: Samsung QE55Q70C | console: PS5";
  await call("/v1/reports", { method: "POST", body: report({ device: `${device}\n` + "x".repeat(2000) }) });
  await call("/v1/reports", { method: "POST", body: report() });
  await call("/v1/reports", { method: "POST", body: report({ device: 42 }) });
  const list = await (await call("/v1/reports", { token: TOKEN })).json();
  const devices = list.reports.map((r) => r.device).sort((a, b) => b.length - a.length);
  assert.equal(devices[0].length, 600);
  assert.ok(devices[0].startsWith(`${device} xxx`));
  assert.deepEqual(devices.slice(1), ["", ""]);
});
