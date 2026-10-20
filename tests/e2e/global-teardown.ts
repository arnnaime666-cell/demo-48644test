import { purgeTestFixtures } from './helpers/supabase';

/**
 * Stale E2E fixture sweep.
 *
 * Test accounts, sessions, admin logs, and financial ledger rows created by
 * E2E runs are not production records. The database owns the purge order so
 * future tests do not leave auth users, profiles, sessions, or fake ledger
 * entries behind.
 */
const STALE_AFTER_MS = 0;
const SWEEP_BATCH = 500;

export default async function globalTeardown() {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    console.log('[e2e sweep] Supabase service env missing; skipping stale fixture sweep.');
    return;
  }

  try {
    const cutoff = STALE_AFTER_MS > 0 ? new Date(Date.now() - STALE_AFTER_MS).toISOString() : null;
    const result = await purgeTestFixtures({ cutoff, limit: SWEEP_BATCH });
    console.log('[e2e sweep] purged stale fixtures:', JSON.stringify(result));
  } catch (error) {
    // The sweep is hygiene, not a gate — never fail the suite over it.
    console.warn('[e2e sweep] stale fixture sweep failed:', error);
  }
}
