import path from 'path'
import { defineConfig } from 'vitest/config'

// Unit tests for the frontend's pure logic (app/frontend/**/*.test.ts). Kept
// apart from vite.config.ts so they don't need the Rails/Vite Ruby plugin.
export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(import.meta.dirname, './app/frontend'),
    },
  },
  test: {
    include: ['app/frontend/**/*.test.ts'],
    environment: 'node',
  },
})
