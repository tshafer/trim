import type { Ctx } from "@shaferllc/keel/core";
import { view } from "@shaferllc/keel/core";

import Home from "../../resources/views/home.js";

export class HomeController {
  async index(c: Ctx) {
    return c.html(await view(Home, {}));
  }
}
