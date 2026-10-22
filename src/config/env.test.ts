import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";

test("ingestion jobs can load configuration without Google authentication", () => {
  const childEnv = { ...process.env };
  delete childEnv.GOOGLE_CLIENT_ID;
  const result = spawnSync(
    process.execPath,
    ["--import", "tsx", "--input-type=module", "-e", 'await import("./src/config/env.ts")'],
    { env: childEnv, encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
});
