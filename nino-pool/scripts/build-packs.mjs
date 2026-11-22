// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Nino: oyun paketlerini YEREL D1'den elle üretir (sunucunun günlük üretimiyle aynı kod: src/packs.js).
// Kullanım (nino-pool içinde, önce `npx wrangler d1 migrations apply nino-pool --local`):
//   node scripts/build-packs.mjs [dil=tr] [--out klasör]
// --out verilirse üretilen dosyalar `<klasör>/<id>.json.gz` olarak da yazılır (incelemek için).
// Yalnız yerel veritabanına dokunur; canlıda üretim günlük zamanlayıcıyla ya da POST /v1/packs/build ile yapılır.
import { getPlatformProxy } from "wrangler";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { buildPacks, listPacks, readPack } from "../src/packs.js";

const args = process.argv.slice(2);
const outAt = args.indexOf("--out");
const out = outAt >= 0 ? args.splice(outAt, 2)[1] : null;
const lang = args[0] ?? "tr";

// remoteBindings: false → yapay zekâ bağlaması da dahil hiçbir şey Cloudflare'e bağlanmaz.
const { env, dispose } = await getPlatformProxy({ remoteBindings: false });
try {
  const vars = { PACK_MIN_INSTALLS: process.env.PACK_MIN_INSTALLS ?? env.PACK_MIN_INSTALLS,
    PACK_MIN_LINES: process.env.PACK_MIN_LINES ?? env.PACK_MIN_LINES };
  const result = await buildPacks(env.DB, vars, Math.floor(Date.now() / 1000), lang);
  console.log(JSON.stringify(result));
  for (const p of await listPacks(env.DB, lang)) {
    console.log(`${p.id}\t${p.entries} satır\t${p.size} bayt\tsürüm ${p.version}\t${p.sha256}`);
    if (out) {
      mkdirSync(out, { recursive: true });
      writeFileSync(join(out, `${p.id}.json.gz`), (await readPack(env.DB, lang, p.id)).data);
    }
  }
} finally {
  await dispose();
}
