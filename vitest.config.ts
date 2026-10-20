import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defaultExclude, defineConfig } from 'vitest/config';

// Resolve the same "@/" alias Next.js uses, so unit tests import app code
// the same way the app does.
const rootDir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(rootDir, 'src'),
    },
  },
  test: {
    setupFiles: ['./vitest.setup.ts'],
    // Playwright specs live in tests/e2e and run via `npm run test:e2e` —
    // they cannot execute under vitest.
    exclude: [...defaultExclude, 'tests/e2e/**'],
  },
});