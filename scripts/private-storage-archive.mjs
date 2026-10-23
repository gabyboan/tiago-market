// Service credentials stay in the process environment. Never emit object data.
import { createClient } from "@supabase/supabase-js";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";

const [file, object] = process.argv.slice(2);
const bucket = "catalog-private-archives";
const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!file || (!object && file !== "--initialize") || !url || !key)
  throw new Error("Archive configuration missing");
const client = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const sha = (data) => createHash("sha256").update(data).digest("hex");
try {
  if (file === "--initialize") {
    const { error } = await client.storage.createBucket(bucket, {
      public: false,
      fileSizeLimit: 50 * 1024 * 1024,
      allowedMimeTypes: ["application/gzip", "application/json"],
    });
    if (error) throw new Error("Private archive bucket unavailable");
    console.log(JSON.stringify({ bucket, public: false }));
    process.exit(0);
  }
  const { data: existing, error: lookup } =
    await client.storage.getBucket(bucket);
  if (lookup) throw new Error("Private archive bucket unavailable");
  if (existing.public) throw new Error("Archive bucket must be private");
  const body = await readFile(file);
  const { error: upload } = await client.storage
    .from(bucket)
    .upload(object, body, {
      contentType: file.endsWith(".gz")
        ? "application/gzip"
        : "application/json",
      upsert: false,
    });
  if (upload) throw new Error("Archive upload failed");
  const { data, error: download } = await client.storage
    .from(bucket)
    .download(object);
  if (download) throw new Error("Archive verification download failed");
  const restored = Buffer.from(await data.arrayBuffer());
  if (sha(restored) !== sha(body))
    throw new Error("Remote archive checksum mismatch");
  console.log(
    JSON.stringify({
      bucket,
      object,
      bytes: body.length,
      sha256: sha(body),
      verified: true,
    }),
  );
} catch (error) {
  // SDK errors may include request details; expose only our controlled messages.
  const allowed = [
    "Private archive bucket unavailable",
    "Archive bucket must be private",
    "Archive upload failed",
    "Archive verification download failed",
    "Remote archive checksum mismatch",
  ];
  console.error(
    allowed.includes(error.message)
      ? error.message
      : "Private archive operation failed",
  );
  process.exitCode = 1;
}
