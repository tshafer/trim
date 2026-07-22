import type { Router, Ctx } from "@shaferllc/keel/core";

import { HomeController } from "../app/Controllers/HomeController.js";

/**
 * Handlers are a [Controller, method] tuple (resolved from the container) or an
 * inline closure.
 */
export default function routes(router: Router): void {
  router.get("/", [HomeController, "index"]);
  router.get("/health", (c: Ctx) => c.json({ ok: true }));
  // Convenience redirect so trim.shafer.llc/download goes straight to the dmg.
  router.get("/download", (c: Ctx) =>
    c.redirect("https://github.com/tshafer/trim/releases/latest", 302),
  );
}
