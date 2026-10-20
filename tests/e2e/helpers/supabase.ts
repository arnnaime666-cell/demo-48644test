import fs from 'node:fs';
import path from 'node:path';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { UserRole } from '../../../src/types';

function loadEnvFile() {
  const envPath = path.join(process.cwd(), '.env.local');
  if (!fs.existsSync(envPath)) return;

  for (const rawLine of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const match = line.match(/^([^=]+)=(.*)$/);
    if (!match) continue;
    const key = match[1].trim();
    if (process.env[key]) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

loadEnvFile();

export function getServiceSupabase(): SupabaseClient {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error('E2E tests require NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY');
  }

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export const E2E_PASSWORD = 'EducateED2026!';

interface PurgeTestFixturesOptions {
  cutoff?: string | null;
  limit?: number;
  includeScrubbed?: boolean;
}

/**
 * Purges E2E/test fixtures through the database-owned cleanup function.
 * The RPC owns delete ordering and intentionally removes test-created
 * financial/admin rows too — those are fixtures, not production records.
 */
export async function purgeTestFixtures(options: PurgeTestFixturesOptions = {}) {
  const supabase = getServiceSupabase();
  const { data, error } = await supabase.rpc('purge_test_fixtures', {
    p_cutoff: options.cutoff ?? null,
    p_limit: options.limit ?? 500,
    p_include_scrubbed: options.includeScrubbed ?? true,
  });

  if (error) throw error;
  return data;
}

export async function cleanupUsersByEmail(emails: string[]) {
  if (process.env.CI || emails.length === 0) return;
  await purgeTestFixtures({ limit: Math.max(emails.length, 25) });
}

export async function cleanupE2EUsersByEmail(emails: string[]) {
  if (process.env.CI || emails.length === 0) return;
  await purgeTestFixtures({ limit: Math.max(emails.length, 25) });
}

export async function createE2EUser(input: {
  email: string;
  fullName: string;
  role: UserRole;
  phone?: string;
  province?: string;
}) {
  const supabase = getServiceSupabase();
  const { data, error } = await supabase.auth.admin.createUser({
    email: input.email,
    password: E2E_PASSWORD,
    email_confirm: true,
    user_metadata: {
      full_name: input.fullName,
      role: input.role,
      phone: input.phone ?? '',
      province: input.province ?? 'Ontario',
    },
  });

  if (error || !data.user) {
    throw new Error(error?.message ?? `Failed to create ${input.role} E2E user`);
  }

  const now = new Date().toISOString();
  const { error: profileError } = await supabase.from('profiles').upsert(
    {
      id: data.user.id,
      email: input.email,
      full_name: input.fullName,
      role: input.role,
      phone: input.phone ?? null,
      province: input.province ?? 'Ontario',
      email_verified: true,
      email_confirmed_at: now,
      phone_verified: true,
      terms_accepted_at: now,
      terms_version: '2026-04-01',
      commission_accepted_at: input.role === 'tutor' ? now : null,
      commission_version: input.role === 'tutor' ? '2026-04-01' : null,
      subscription_tier: input.role === 'parent' || input.role === 'student' ? 'basic' : null,
      subscription_status: input.role === 'parent' || input.role === 'student' ? 'active' : 'inactive',
      children_info: input.role === 'parent'
        ? [{ name: 'E2E Learner', grade: 'Grade 4', subjects: ['Mathematics'], preferredLanguage: 'English' }]
        : null,
    },
    { onConflict: 'id' }
  );

  if (profileError) {
    await supabase.auth.admin.deleteUser(data.user.id);
    throw profileError;
  }

  return data.user.id;
}

export async function getLatestOtpCode(email: string, type: 'email' | 'phone'): Promise<string> {
  const supabase = getServiceSupabase();
  const deadline = Date.now() + 15_000;

  while (Date.now() < deadline) {
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('id')
      .eq('email', email)
      .maybeSingle();

    if (profileError) throw profileError;

    if (profile?.id) {
      const { data: code, error: codeError } = await supabase
        .from('verification_codes')
        .select('code')
        .eq('user_id', profile.id)
        .eq('type', type)
        .eq('used', false)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (codeError) throw codeError;
      if (code?.code) return code.code;
    }

    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  throw new Error(`Timed out waiting for ${type} OTP for ${email}`);
}

export async function getProfileByEmail(email: string) {
  const supabase = getServiceSupabase();
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('email', email)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function getTutorByEmail(email: string) {
  const supabase = getServiceSupabase();
  const profile = await getProfileByEmail(email);
  if (!profile) return null;
  const { data, error } = await supabase
    .from('tutors')
    .select('*')
    .eq('id', profile.id)
    .maybeSingle();
  if (error) throw error;
  return data;
}
