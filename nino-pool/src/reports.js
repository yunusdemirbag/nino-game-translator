// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Sorun Bildir". Uygulamalar açıklamayı, isteğe bağlı iletişim bilgisini, günlüğü ve en çok 3 ekran görüntüsünü
// (base64 JPEG/PNG) gönderir. Fotoğraflar D1'de BLOB olarak tutulur (satır sınırı 2 MB; uygulama küçültüp gönderir).

import { saltedDigest } from "./key.js";

export const REPORT_LIMITS = {
  maxBodyBytes: 4 * 1024 * 1024,
  maxText: 4000,
  maxContact: 200,
  maxLog: 60000,
  maxDevice: 600,
  maxImages: 3,
  maxImageBytes: 1500 * 1024,
  perInstallPerDay: 10,
};

const PLATFORMS = new Set(["mac", "windows", "linux", "android", "ios", "tv"]);
const MIMES = new Set(["image/jpeg", "image/png", "image/webp", "image/heic"]);
const clip = (value, max) => (typeof value === "string" ? value.slice(0, max) : "");

function decodeBase64(text) {
  if (typeof text !== "string" || !/^[A-Za-z0-9+/=\s]+$/.test(text)) return null;
  try {
    const binary = atob(text.replace(/\s+/g, ""));
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/** Bildirimi doğrular ve yazar. Döner: { status, body, retryAfter? }. */
export async function receiveReport(db, env, body, now) {
  if (!body || typeof body !== "object" || body.v !== 1) return { status: 400, body: { ok: false, error: "bad_report" } };
  const text = clip(body.text, REPORT_LIMITS.maxText).trim();
  const install = typeof body.install === "string" ? body.install : "";
  if (!text || install.length < 8 || install.length > 64) return { status: 400, body: { ok: false, error: "bad_report" } };
  const platform = PLATFORMS.has(body.platform) ? body.platform : "";
  if (!platform) return { status: 400, body: { ok: false, error: "bad_platform" } };
  const images = Array.isArray(body.images) ? body.images : [];
  if (images.length > REPORT_LIMITS.maxImages) return { status: 400, body: { ok: false, error: "too_many_images" } };
  const decoded = [];
  for (const image of images) {
    const mime = MIMES.has(image?.mime) ? image.mime : null;
    const bytes = decodeBase64(image?.data);
    if (!mime || !bytes || bytes.length === 0) return { status: 400, body: { ok: false, error: "bad_image" } };
    if (bytes.length > REPORT_LIMITS.maxImageBytes) return { status: 413, body: { ok: false, error: "image_too_large" } };
    decoded.push({ mime, bytes });
  }

  const hashed = await saltedDigest(install, env.INSTALL_SALT ?? "");
  const today = await db.prepare("SELECT COUNT(*) AS n FROM reports WHERE install = ? AND created > ?")
    .bind(hashed, now - 86400).first("n");
  if ((today ?? 0) >= REPORT_LIMITS.perInstallPerDay) return { status: 429, body: { ok: false, error: "rate_limited" }, retryAfter: 3600 };

  const id = crypto.randomUUID();
  const statements = [
    db.prepare("INSERT INTO reports (id, created, install, app, platform, language, text, contact, log, images, device) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
      .bind(id, now, hashed, clip(body.app, 40), platform, clip(body.language, 16), text,
        clip(body.contact, REPORT_LIMITS.maxContact).trim(), clip(body.log, REPORT_LIMITS.maxLog), decoded.length,
        cleanDevice(body.device)),
    ...decoded.map((image, idx) =>
      db.prepare("INSERT INTO report_images (report, idx, mime, data) VALUES (?, ?, ?, ?)").bind(id, idx, image.mime, image.bytes)),
  ];
  await db.batch(statements);
  return { status: 200, body: { ok: true, id } };
}

/**
 * Cihaz bilgileri (uygulamaların DeviceInfo özeti: "app: 3.4.0 (19) | device: Mac16,1 | system: macOS 27.0 | tv: …").
 * Tek satır, en çok 600 karakter; eski sürümler göndermez (boş kalır).
 */
export function cleanDevice(value) {
  return clip(value, REPORT_LIMITS.maxDevice).replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
}

/** En yeni bildirimler (günlük metni hariç, kısaltılmış). */
export async function listReports(db, { limit = 50, before } = {}) {
  const max = Math.min(200, Math.max(1, Number.parseInt(limit, 10) || 50));
  const cursor = Number.parseInt(before, 10);
  const { results } = await db.prepare(
    `SELECT id, created, app, platform, language, text, contact, images, status, device, length(log) AS log_length
       FROM reports ${Number.isFinite(cursor) ? "WHERE created < ?" : ""} ORDER BY created DESC LIMIT ?`)
    .bind(...(Number.isFinite(cursor) ? [cursor, max] : [max])).all();
  return results;
}

export async function getReport(db, id) {
  return db.prepare("SELECT id, created, app, platform, language, text, contact, log, images, status, device FROM reports WHERE id = ?")
    .bind(id).first();
}

export async function getReportImage(db, id, idx) {
  return db.prepare("SELECT mime, data FROM report_images WHERE report = ? AND idx = ?").bind(id, idx).first();
}

export async function setReportStatus(db, id, status) {
  if (!["new", "seen", "done"].includes(status)) return false;
  const result = await db.prepare("UPDATE reports SET status = ? WHERE id = ?").bind(status, id).run();
  return (result.meta?.changes ?? 0) > 0;
}
