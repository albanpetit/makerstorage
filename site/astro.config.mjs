// @ts-check
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";

// Served by GitHub Pages on the custom domain https://makerstorage.io/. The
// deploy workflow passes the real origin and base path (a /<repo>/ prefix if the
// custom domain is ever removed), so these defaults only matter locally.
export default defineConfig({
  site: process.env.SITE_URL || "https://makerstorage.io",
  base: process.env.BASE_PATH || "/",
  trailingSlash: "always",
  integrations: [sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
});
