import { expect, test, type APIRequestContext, type Browser, type BrowserContext } from '@playwright/test';
import {
  cleanupE2EUsersByEmail,
  createE2EUser,
  E2E_PASSWORD,
  getServiceSupabase,
} from './helpers/supabase';
import { uniqueCanadianPhone, uniqueEmail } from './helpers/ui';
import { parseWallClockInTimeZone } from '../../src/lib/zoned-time';

const SUBJECT = 'Mathematics';
const GRADE_LEVEL = 'Grade 4';
const POLICY_VERSION = '2026-06-02';

type AuthenticatedContext = {
  context: BrowserContext;
  request: APIRequestContext;
};

async function signIn(browser: Browser, email: string): Promise<AuthenticatedContext> {
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto('/login');
  await page.getByLabel(/email/i).fill(email);
  await page.getByLabel(/password/i).fill(E2E_PASSWORD);
  await page.getByRole('button', { name: /sign in/i }).click();
  await expect(page).toHaveURL(/\/(admin|family|tutor|student)$/);
  await page.close();

  return { context, request: context.request };
}

async function createApprovedTutor(email: string, overrides: Record<string, unknown> = {}) {
  const tutorId = await createE2EUser({
    email,
    fullName: `Lifecycle Tutor ${email}`,
    role: 'tutor',
    phone: uniqueCanadianPhone(),
  });

  const supabase = getServiceSupabase();
  const { error } = await supabase.from('tutors').upsert(
    {
      id: tutorId,
      bio: 'Experienced mathematics tutor for lifecycle e2e coverage.',
      subjects: [SUBJECT],
      grade_levels: [GRADE_LEVEL],
      curriculum_tags: ['Ontario'],
      languages: ['English'],
      hourly_rate: 6000,
      session_duration: 60,
      commission_tier: 'starter',
      application_status: 'approved',
      quality_status: 'good',
      stripe_account_id: null,
      stripe_account_status: 'pending',
      is_active: true,
      ...overrides,
    },
    { onConflict: 'id' }
  );
  if (error) throw error;

  return tutorId;
}

async function createParent(email: string) {
  return createE2EUser({
    email,
    fullName: `Lifecycle Parent ${email}`,
    role: 'parent',
    phone: uniqueCanadianPhone(),
  });
}

async function createAdmin(email: string) {
  return createE2EUser({
    email,
    fullName: `Lifecycle Admin ${email}`,
    role: 'admin',
    phone: uniqueCanadianPhone(),
  });
}

function localFutureSlot(daysFromNow: number, hour = 15) {
  const timeZone = 'America/Toronto';
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const localDate = new Date(Date.UTC(
    Number(values.year),
    Number(values.month) - 1,
    Number(values.day) + daysFromNow
  ));

  const yyyy = localDate.getUTCFullYear();
  const mm = String(localDate.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(localDate.getUTCDate()).padStart(2, '0');
  const hh = String(hour).padStart(2, '0');
  const scheduledDate = `${yyyy}-${mm}-${dd}`;
  const scheduledTime = `${hh}:00`;
  const parsed = parseWallClockInTimeZone(scheduledDate, scheduledTime, timeZone);

  if ('error' in parsed) {
    throw new Error(parsed.error);
  }

  return {
    scheduledAt: parsed.date,
    scheduledDate,
    scheduledTime,
    dayOfWeek: localDate.getUTCDay(),
  };
}

async function createSession(input: {
  tutorId: string;
  studentId: string;
  scheduledAt: Date;
  status?: string;
  paymentStatus?: string;
  payoutStatus?: string;
  payoutAt?: string | null;
  tutorFeedbackSubmittedAt?: string | null;
  stripePaymentIntentId?: string | null;
}) {
  const supabase = getServiceSupabase();
  const [{ data: child }, childColumn] = await Promise.all([
    supabase
      .from('children')
      .select('id')
      .eq('parent_id', input.studentId)
      .limit(1)
      .maybeSingle(),
    supabase.from('sessions').select('child_id').limit(1),
  ]);
  const priceCents = 6000;
  const platformFeeCents = 1200;
  const learnerFields = !childColumn.error && child?.id
    ? { child_id: child.id }
    : {};
  const { data, error } = await supabase
    .from('sessions')
    .insert({
      tutor_id: input.tutorId,
      student_id: input.studentId,
      ...learnerFields,
      subject: SUBJECT,
      grade_level: GRADE_LEVEL,
      scheduled_at: input.scheduledAt.toISOString(),
      duration_minutes: 60,
      price_cents: priceCents,
      platform_fee_cents: platformFeeCents,
      tutor_payout_cents: priceCents - platformFeeCents,
      booking_type: 'scheduled',
      on_demand_premium_cents: 0,
      status: input.status ?? 'confirmed',
      payment_provider: input.stripePaymentIntentId ? 'stripe' : null,
      payment_reference_id: input.stripePaymentIntentId ?? null,
      stripe_payment_intent_id: input.stripePaymentIntentId ?? null,
      payment_status: input.paymentStatus ?? 'paid',
      payout_status: input.payoutStatus ?? 'pending',
      payout_at: input.payoutAt ?? null,
      tutor_feedback_submitted_at: input.tutorFeedbackSubmittedAt ?? null,
      tutor_feedback: input.tutorFeedbackSubmittedAt
        ? {
            attendance: 'attended',
            covered: 'Fractions and ratios',
            engagement: 'Focused',
            improvementSignal: 'Solved examples independently',
            nextSteps: 'Practice multi-step word problems',
            supportConcern: null,
          }
        : null,
      policy_accepted_at: new Date().toISOString(),
      policy_version: POLICY_VERSION,
    })
    .select('*')
    .single();

  if (error || !data) throw error ?? new Error('Failed to create E2E session');
  return data;
}

test.describe('Sprint 4 lifecycle coverage', () => {
  test('covers dispute submission and all admin dispute decisions without releasing payout early', async ({ browser }) => {
    const parentEmail = uniqueEmail('e2e-dispute-parent');
    const tutorEmail = uniqueEmail('e2e-dispute-tutor');
    const adminEmail = uniqueEmail('e2e-dispute-admin');
    const emails = [parentEmail, tutorEmail, adminEmail];
    await cleanupE2EUsersByEmail(emails);

    let parentAuth: AuthenticatedContext | null = null;
    let adminAuth: AuthenticatedContext | null = null;

    try {
      const [parentId, tutorId] = await Promise.all([
        createParent(parentEmail),
        createApprovedTutor(tutorEmail),
        createAdmin(adminEmail),
      ]).then(([parent, tutor]) => [parent, tutor]);

      const completedAt = new Date(Date.now() - 60 * 60 * 1000);
      const tutorFeedbackSubmittedAt = new Date(Date.now() - 30 * 60 * 1000).toISOString();
      const session = await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: completedAt,
        status: 'completed',
        payoutStatus: 'scheduled',
        payoutAt: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
        tutorFeedbackSubmittedAt,
      });

      parentAuth = await signIn(browser, parentEmail);
      const open = await parentAuth.request.post(`/api/sessions/${session.id}/dispute`, {
        data: {
          reason: 'The session ended early and the tutor did not cover the requested lesson goals.',
          reasonCategory: 'session_quality',
          requestedRefundCents: 2500,
        },
      });
      expect(open.status()).toBe(200);

      const supabase = getServiceSupabase();
      const { data: openDispute } = await supabase
        .from('session_disputes')
        .select('*')
        .eq('session_id', session.id)
        .single();
      expect(openDispute).toMatchObject({
        status: 'open',
        requested_refund_cents: 2500,
      });

      const { data: heldSession } = await supabase
        .from('sessions')
        .select('status, payout_status, payout_at')
        .eq('id', session.id)
        .single();
      expect(heldSession).toMatchObject({
        status: 'disputed',
        payout_status: 'pending',
        payout_at: null,
      });

      // Admin resolution enforces MIN_DISPUTE_AGE_HOURS (24h) unless the tutor
      // has submitted a statement; age the dispute so decisions can proceed.
      const agedCreatedAt = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
      const { error: ageError } = await supabase
        .from('session_disputes')
        .update({ created_at: agedCreatedAt })
        .eq('id', openDispute.id);
      if (ageError) throw ageError;

      adminAuth = await signIn(browser, adminEmail);
      const reject = await adminAuth.request.patch(`/api/admin/disputes/${openDispute.id}`, {
        data: {
          status: 'rejected',
          adminNotes: 'Session logs show the tutor attended and completed the planned lesson.',
        },
      });
      expect(reject.status()).toBe(200);

      const { data: rejectedSession } = await supabase
        .from('sessions')
        .select('status, payout_status, payout_at')
        .eq('id', session.id)
        .single();
      expect(rejectedSession?.status).toBe('completed');
      expect(rejectedSession?.payout_status).toBe('scheduled');
      expect(rejectedSession?.payout_at).toBeTruthy();

      for (const status of ['approved', 'partially_approved'] as const) {
        const decisionSession = await createSession({
          tutorId,
          studentId: parentId,
          scheduledAt: new Date(Date.now() - 2 * 60 * 60 * 1000),
          status: 'completed',
          payoutStatus: 'scheduled',
          payoutAt: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
          tutorFeedbackSubmittedAt,
          // A placeholder intent id satisfies the paid-session pre-checks but
          // guarantees any real refund attempt fails at Stripe, letting this
          // spec pin the refund-failure atomicity boundary in every env.
          stripePaymentIntentId: `pi_e2e_dispute_${status}`,
        });

        const { data: dispute, error } = await supabase
          .from('session_disputes')
          .insert({
            session_id: decisionSession.id,
            student_id: parentId,
            tutor_id: tutorId,
            reason: `Admin ${status} lifecycle decision fixture`,
            requested_refund_cents: 2500,
            // Old enough to clear the MIN_DISPUTE_AGE_HOURS resolution gate.
            created_at: agedCreatedAt,
          })
          .select('*')
          .single();
        if (error || !dispute) throw error ?? new Error('Failed to seed dispute decision fixture');

        // L24/L25: approvals must carry a positive refund amount.
        const zeroCentDecision = await adminAuth.request.patch(`/api/admin/disputes/${dispute.id}`, {
          data: {
            status,
            approvedRefundCents: 0,
            adminNotes: `${status} zero-cent decision must be rejected`,
          },
        });
        expect(zeroCentDecision.status()).toBe(400);
        await expect(zeroCentDecision.json()).resolves.toMatchObject({
          error: 'A positive refund amount is required for approved and partially approved disputes',
        });

        // A failed Stripe refund must not record the decision (the placeholder
        // payment intent cannot be refunded in any environment).
        const failedRefundDecision = await adminAuth.request.patch(`/api/admin/disputes/${dispute.id}`, {
          data: {
            status,
            approvedRefundCents: 2500,
            adminNotes: `${status} decision with unrefundable payment intent`,
          },
        });
        expect(failedRefundDecision.status()).toBe(502);
        await expect(failedRefundDecision.json()).resolves.toMatchObject({
          error: 'Refund failed; dispute decision was not recorded',
        });

        // Both rejected attempts must leave the dispute open, unresolved, and
        // the payout untouched.
        const { data: unresolved } = await supabase
          .from('session_disputes')
          .select('status, approved_refund_cents, resolved_at, admin_id')
          .eq('id', dispute.id)
          .single();
        expect(unresolved).toMatchObject({
          status: 'open',
          resolved_at: null,
        });

        const { data: untouchedSession } = await supabase
          .from('sessions')
          .select('payout_status')
          .eq('id', decisionSession.id)
          .single();
        expect(untouchedSession?.payout_status).toBe('scheduled');
      }
    } finally {
      await parentAuth?.context.close();
      await adminAuth?.context.close();
      await cleanupE2EUsersByEmail(emails);
    }
  });

  test('covers cancellation windows and prevents repeat cancellation refund attempts', async ({ browser }) => {
    const parentEmail = uniqueEmail('e2e-cancel-parent');
    const tutorEmail = uniqueEmail('e2e-cancel-tutor');
    const emails = [parentEmail, tutorEmail];
    await cleanupE2EUsersByEmail(emails);

    let parentAuth: AuthenticatedContext | null = null;

    try {
      const parentId = await createParent(parentEmail);
      const tutorId = await createApprovedTutor(tutorEmail);

      const futureRefundable = await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: new Date(Date.now() + 30 * 60 * 60 * 1000),
        status: 'confirmed',
      });
      const futureLate = await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: new Date(Date.now() + 2 * 60 * 60 * 1000),
        status: 'confirmed',
      });

      parentAuth = await signIn(browser, parentEmail);
      const refundableCancel = await parentAuth.request.post(`/api/sessions/${futureRefundable.id}/cancel`, {
        data: { reason: 'Family schedule changed more than a day before the session.' },
      });
      expect(refundableCancel.status()).toBe(200);
      await expect(refundableCancel.json()).resolves.toMatchObject({
        success: true,
        refundIssued: false,
        message: 'Session cancelled. No payment was made to refund.',
      });

      const repeatedCancel = await parentAuth.request.post(`/api/sessions/${futureRefundable.id}/cancel`, {
        data: { reason: 'Trying to cancel the same session again.' },
      });
      expect(repeatedCancel.status()).toBe(400);
      await expect(repeatedCancel.json()).resolves.toMatchObject({
        error: 'This session cannot be cancelled',
      });

      const lateCancel = await parentAuth.request.post(`/api/sessions/${futureLate.id}/cancel`, {
        data: { reason: 'Family schedule changed inside the cancellation window.' },
      });
      expect(lateCancel.status()).toBe(200);
      await expect(lateCancel.json()).resolves.toMatchObject({
        success: true,
        refundIssued: false,
        message: 'Session cancelled. Refund not available within 24 hours.',
      });
    } finally {
      await parentAuth?.context.close();
      await cleanupE2EUsersByEmail(emails);
    }
  });

  test('covers checkout double-booking guards at the API and database race boundary', async ({ browser }) => {
    const parentEmail = uniqueEmail('e2e-double-parent');
    const secondParentEmail = uniqueEmail('e2e-double-second-parent');
    const tutorEmail = uniqueEmail('e2e-double-tutor');
    const emails = [parentEmail, secondParentEmail, tutorEmail];
    await cleanupE2EUsersByEmail(emails);

    let parentAuth: AuthenticatedContext | null = null;

    try {
      const [parentId, secondParentId] = await Promise.all([
        createParent(parentEmail),
        createParent(secondParentEmail),
      ]);
      const tutorId = await createApprovedTutor(tutorEmail, {
        // Unique per run: tutors.stripe_account_id has a unique index, and a
        // leftover row from a previously interrupted run would collide with a
        // fixed placeholder value.
        stripe_account_id: `acct_e2e_${Date.now()}_${Math.floor(Math.random() * 1e6)}`,
        stripe_account_status: 'active',
      });

      const slot = localFutureSlot(5, 16);
      const supabase = getServiceSupabase();
      const { error: slotError } = await supabase.from('availability_slots').insert({
        tutor_id: tutorId,
        day_of_week: slot.dayOfWeek,
        start_time: `${slot.scheduledTime}:00`,
        end_time: '17:00:00',
        is_active: true,
      });
      if (slotError) throw slotError;

      await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: slot.scheduledAt,
        status: 'pending',
      });

      const { data: secondParentChild, error: childError } = await supabase
        .from('children')
        .select('id')
        .eq('parent_id', secondParentId)
        .single();
      if (childError || !secondParentChild) {
        throw childError ?? new Error('Failed to load the E2E learner');
      }

      parentAuth = await signIn(browser, secondParentEmail);
      const apiConflict = await parentAuth.request.post('/api/payments/checkout', {
        data: {
          tutor_id: tutorId,
          child_id: secondParentChild.id,
          subject: SUBJECT,
          grade_level: GRADE_LEVEL,
          scheduled_date: slot.scheduledDate,
          scheduled_time: slot.scheduledTime,
          timezone: 'America/Toronto',
          policy_accepted: true,
          policy_version: POLICY_VERSION,
        },
      });
      expect(apiConflict.status()).toBe(409);
      await expect(apiConflict.json()).resolves.toMatchObject({
        error: 'Selected time has already been booked',
      });

      const raceSlot = localFutureSlot(6, 16);
      const firstInsert = {
        tutor_id: tutorId,
        student_id: parentId,
        subject: SUBJECT,
        grade_level: GRADE_LEVEL,
        scheduled_at: raceSlot.scheduledAt.toISOString(),
        duration_minutes: 60,
        price_cents: 6000,
        platform_fee_cents: 1200,
        tutor_payout_cents: 4800,
        status: 'pending',
      };
      const secondInsert = { ...firstInsert, student_id: secondParentId };
      const results = await Promise.all([
        supabase.from('sessions').insert(firstInsert).select('id').single(),
        supabase.from('sessions').insert(secondInsert).select('id').single(),
      ]);

      const successes = results.filter((result) => !result.error);
      const conflicts = results.filter((result) => result.error?.code === '23505');
      expect(successes).toHaveLength(1);
      expect(conflicts).toHaveLength(1);
    } finally {
      await parentAuth?.context.close();
      await cleanupE2EUsersByEmail(emails);
    }
  });

  test('covers tutor quality auto-flagging, availability behavior, valid transitions, and invalid jumps', async ({ browser }) => {
    const parentEmail = uniqueEmail('e2e-quality-parent');
    const tutorEmail = uniqueEmail('e2e-quality-tutor');
    const adminEmail = uniqueEmail('e2e-quality-admin');
    const emails = [parentEmail, tutorEmail, adminEmail];
    await cleanupE2EUsersByEmail(emails);

    let parentAuth: AuthenticatedContext | null = null;
    let adminAuth: AuthenticatedContext | null = null;

    try {
      const parentId = await createParent(parentEmail);
      const tutorId = await createApprovedTutor(tutorEmail);
      await createAdmin(adminEmail);

      const session = await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: new Date(Date.now() - 60 * 60 * 1000),
        status: 'completed',
      });

      const supabase = getServiceSupabase();
      const { error: reviewError } = await supabase.from('reviews').insert({
        session_id: session.id,
        tutor_id: tutorId,
        student_id: parentId,
        rating: 2,
        comment: 'The session was not useful.',
      });
      if (reviewError) throw reviewError;

      const { data: flaggedTutor } = await supabase
        .from('tutors')
        .select('rating_avg, total_sessions, quality_status, is_active, quality_flagged_at')
        .eq('id', tutorId)
        .single();
      expect(flaggedTutor).toMatchObject({
        rating_avg: 2,
        total_sessions: 1,
        quality_status: 'flagged',
      });
      expect(typeof flaggedTutor?.is_active).toBe('boolean');
      expect(flaggedTutor?.quality_flagged_at).toBeTruthy();

      parentAuth = await signIn(browser, parentEmail);
      const flaggedAvailability = await parentAuth.request.get(`/api/tutors/${tutorId}/availability`);
      if (flaggedTutor?.is_active) {
        expect(flaggedAvailability.status()).toBe(200);
      } else {
        expect(flaggedAvailability.status()).toBe(400);
        await expect(flaggedAvailability.json()).resolves.toMatchObject({
          error: 'Tutor is not available',
        });
      }

      adminAuth = await signIn(browser, adminEmail);
      const invalidJump = await adminAuth.request.patch(`/api/admin/tutors/${tutorId}/quality`, {
        data: { status: 'banned', notes: 'Skipping required transition steps should fail.' },
      });
      expect(invalidJump.status()).toBe(400);
      await expect(invalidJump.json()).resolves.toMatchObject({
        error: expect.stringContaining('Invalid quality status transition from flagged to banned'),
      });

      for (const status of ['warned', 'suspended', 'banned'] as const) {
        const response = await adminAuth.request.patch(`/api/admin/tutors/${tutorId}/quality`, {
          data: {
            status,
            notes: `E2E quality transition to ${status}`,
            suspendedUntil: status === 'suspended'
              ? new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
              : undefined,
          },
        });
        const responseBody = await response.json();
        expect(response.status(), `${status}: ${JSON.stringify(responseBody)}`).toBe(200);
      }

      const { data: finalTutor } = await supabase
        .from('tutors')
        .select('quality_status, is_active')
        .eq('id', tutorId)
        .single();
      expect(finalTutor).toMatchObject({
        quality_status: 'banned',
        is_active: false,
      });

      const { count: qualityLogs } = await supabase
        .from('admin_logs')
        .select('id', { count: 'exact', head: true })
        .eq('target_id', tutorId)
        .in('action', ['quality_warned', 'quality_suspended', 'quality_banned']);
      expect(qualityLogs).toBe(3);
    } finally {
      await parentAuth?.context.close();
      await adminAuth?.context.close();
      await cleanupE2EUsersByEmail(emails);
    }
  });

  test('covers payout cron execution for due, disputed, and feedback-missing sessions', async ({ browser }) => {
    const parentEmail = uniqueEmail('e2e-payout-parent');
    const tutorEmail = uniqueEmail('e2e-payout-tutor');
    const emails = [parentEmail, tutorEmail];
    await cleanupE2EUsersByEmail(emails);

    let parentAuth: AuthenticatedContext | null = null;

    try {
      const parentId = await createParent(parentEmail);
      const tutorId = await createApprovedTutor(tutorEmail);
      const dueAt = new Date(Date.now() - 60 * 60 * 1000);
      const payoutAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
      const feedbackAt = new Date(Date.now() - 30 * 60 * 1000).toISOString();

      const dueNoStripe = await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: dueAt,
        status: 'completed',
        payoutStatus: 'scheduled',
        payoutAt,
        tutorFeedbackSubmittedAt: feedbackAt,
      });
      const openDispute = await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: new Date(Date.now() - 2 * 60 * 60 * 1000),
        status: 'completed',
        payoutStatus: 'scheduled',
        payoutAt,
        tutorFeedbackSubmittedAt: feedbackAt,
      });
      const missingFeedback = await createSession({
        tutorId,
        studentId: parentId,
        scheduledAt: new Date(Date.now() - 3 * 60 * 60 * 1000),
        status: 'completed',
        payoutStatus: 'scheduled',
        payoutAt,
        tutorFeedbackSubmittedAt: null,
      });

      const supabase = getServiceSupabase();
      const { error: disputeError } = await supabase.from('session_disputes').insert({
        session_id: openDispute.id,
        student_id: parentId,
        tutor_id: tutorId,
        reason: 'Open dispute should block payout execution.',
        requested_refund_cents: 1000,
      });
      if (disputeError) throw disputeError;

      parentAuth = await signIn(browser, parentEmail);
      const cron = await parentAuth.request.post('/api/sessions/process-payouts');
      expect(cron.status()).toBe(200);
      const body = await cron.json();
      expect(body.processed).toBe(2);
      expect(body.summary).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            session_id: dueNoStripe.id,
            result: expect.objectContaining({ error: 'Tutor has no Stripe account', status: 400 }),
          }),
          expect.objectContaining({
            session_id: openDispute.id,
            result: expect.objectContaining({ error: 'Session has an open dispute', status: 409 }),
          }),
        ])
      );
      expect(body.summary).not.toEqual(
        expect.arrayContaining([expect.objectContaining({ session_id: missingFeedback.id })])
      );

      const { data: sessions } = await supabase
        .from('sessions')
        .select('id, payout_status')
        .in('id', [dueNoStripe.id, openDispute.id, missingFeedback.id]);
      const statuses = new Map((sessions ?? []).map((session) => [session.id, session.payout_status]));
      expect(statuses.get(dueNoStripe.id)).toBe('failed');
      expect(statuses.get(openDispute.id)).toBe('scheduled');
      expect(statuses.get(missingFeedback.id)).toBe('scheduled');
    } finally {
      await parentAuth?.context.close();
      await cleanupE2EUsersByEmail(emails);
    }
  });
});
