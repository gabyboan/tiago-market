import { test } from "node:test";
import assert from "node:assert/strict";
import { detectAccessChallenge } from "./walmart-family.js";

test("detects an access challenge without trying to bypass it", () => {
  assert.match(
    detectAccessChallenge("<html>captcha challenge</html>") ?? "",
    /access challenge \(captcha\)/,
  );
});

test("does not classify an ordinary product page as blocked", () => {
  assert.equal(
    detectAccessChallenge(
      '<script type="application/ld+json">{"@type":"Product"}</script>',
    ),
    null,
  );
});