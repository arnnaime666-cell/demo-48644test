#!/usr/bin/env node
/**
 * Creates a confirmed session for demo purposes — bypasses Stripe.
 * The Daily.co video room works off this session immediately.
 *
 * Usage: node scripts/create-demo-session.mjs
 *
 * Requires .env.local with SUPABASE_SERVICE_ROLE_KEY and NEXT_PUBLIC_SUPABASE_URL.
 */
import fs from 'node:fs';
import path from 'node:path';

const envPath = path.join(process.cwd(), '.env.local');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const match = line.match(/^([^#=]+)=(.*)$/);
    if (match && !process.env[match[1].trim()]) {
      process.env[match[1].trim()] = match[2].trim().replace(/^["']|["']$/g, '');
    }
  }
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local');
  process.exit(1);
}

const PARENT_EMAIL = process.env.DEMO_PARENT_EMAIL ?? 'founder-demo-parent@demo.educateed.ca';
const TUTOR_EMAIL = process.env.DEMO_TUTOR_EMAIL ?? 'founder-demo-tutor@demo.educateed.ca';
const SUBJECT = 'Science';
const GRADE = 'Grade 1';

async function dbFetch(table, query) {
  const url = `${SUPABASE_URL}/rest/v1/${table}?${query}`;
  const res = await fetch(url, {
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
  });
  if (!res.ok) throw new Error(`DB query failed: ${res.status} ${await res.text()}`);
  return res.json();
}

async function main() {
  // Get parent + tutor IDs
  const [parent] = await dbFetch('profiles', `select=id&email=eq.${PARENT_EMAIL}`);
  const [tutor] = await dbFetch('profiles', `select=id&email=eq.${TUTOR_EMAIL}`);
  if (!parent || !tutor) throw new Error('Could not find parent or tutor profile');

  // Schedule 3 min from now
  const scheduledAt = new Date(Date.now() + 3 * 60 * 1000).toISOString();

  const res = await fetch(`${SUPABASE_URL}/rest/v1/sessions`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify({
      tutor_id: tutor.id,
      student_id: parent.id,
      subject: SUBJECT,
      grade_level: GRADE,
      scheduled_at: scheduledAt,
      duration_minutes: 60,
      price_cents: 2000,
      platform_fee_cents: 400,
      tutor_payout_cents: 1600,
      booking_type: 'scheduled',
      status: 'confirmed',
      payment_status: 'paid',
      payout_status: 'pending',
    }),
  });

  if (!res.ok) throw new Error(`Failed to create session: ${res.status} ${await res.text()}`);
  const [session] = await res.json();

  console.log('✅ Demo session created');
  console.log(`   Session ID: ${session.id}`);
  console.log(`   Tutor: ${TUTOR_EMAIL}`);
  console.log(`   Parent: ${PARENT_EMAIL}`);
  console.log(`   Subject: ${SUBJECT}, ${GRADE}`);
  console.log(`   Scheduled: ${scheduledAt}`);
  console.log(`   Status: confirmed, payment: paid`);
  console.log();
  console.log(`   Join at: https://educateed.ca/session/${session.id}/room`);
  console.log();
  console.log('   Room opens 5 min before scheduled time.');
  console.log('   Room expires 60 min after scheduled end.');
}

main().catch((e) => {
  console.error('Error:', e.message);
  process.exit(1);
});
