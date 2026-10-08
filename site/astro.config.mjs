// @ts-check
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";

// GitHub Pages serves the project site from https://<owner>.github.io/<repo>/.
// The deploy workflow passes the real origin and base path (with a custom
// domain the base path is empty), so these defaults only matter locally.
const basePath = process.env.BASE_PATH;

export default defineConfig({
  site: process.env.SITE_URL || "https://albanpetit.github.io",
  base: basePath === undefined ? "/makerstorage" : basePath || "/",
  trailingSlash: "always",
  integrations: [sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
});
