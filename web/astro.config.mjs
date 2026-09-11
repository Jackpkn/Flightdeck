import { readFileSync } from "node:fs";
import { defineConfig } from "astro/config";

// Read the shipped version once, here, where the path is stable. Doing this in
// a page would resolve relative to the bundled prerender chunk, not the source.
const version = readFileSync(new URL("../VERSION", import.meta.url), "utf8").trim();

// Static output: the whole site is HTML and CSS at rest. The only JavaScript
// that ships is the hero's Three.js island, which Vite code-splits into its own
// chunk and the page imports on demand.
export default defineConfig({
  site: "https://flightdeck.app",
  output: "static",
  build: { inlineStylesheets: "always" },
  vite: {
    define: { __FLIGHTDECK_VERSION__: JSON.stringify(version) },
    build: {
      cssMinify: "lightningcss",
      // The Three.js chunk is deliberately large and deliberately lazy — it is
      // never on the first-paint path, so the default warning is noise here.
      chunkSizeWarningLimit: 900,
    },
  },
});
