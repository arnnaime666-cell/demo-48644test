import { expect, test } from '@playwright/test';
import {
  classifyBookingType,
  getPayoutEligibility,
  normalizeTutorFeedback,
} from '../../src/domains/sessions/server/policy';

test.describe('Sprint 4 production hardening rules', () => {
  test('protects session mutation APIs from unauthenticated access', async ({ request }) => {
    const sessionId = '00000000-0000-0000-0000-000000000000';

    const checkout = await request.post('/api/payments/checkout', {
      data: {
        tutor_id: sessionId,
        subject: 'Mathematics',
        grade_level: 'Grade 4',
        scheduled_at: new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString(),
        policy_accepted: true,
        policy_version: '2026-06-02',
      },
    });
    expect(checkout.status()).toBe(401);

    const complete = await request.post('/api/sessions/complete', {
      data: { session_id: sessionId },
    });
    expect(complete.status()).toBe(401);

    const dailyRoom = await request.post('/api/daily/room', {
      data: { session_id: sessionId },
    });
    expect(dailyRoom.status()).toBe(401);

    const start = await request.post(`/api/sessions/${sessionId}/start`);
    expect(start.status()).toBe(401);

    const dispute = await request.post(`/api/sessions/${sessionId}/dispute`, {
      data: { reason: 'The tutor did not attend the booked session.' },
    });
    expect(dispute.status()).toBe(401);
  });

  test('classifies scheduled and on-demand bookings at the 24-hour boundary', () => {
    const now = new Date('2026-06-02T12:00:00.000Z');

    expect(classifyBookingType(new Date('2026-06-03T12:00:00.000Z'), now)).toBe('scheduled');
    expect(classifyBookingType(new Date('2026-06-03T11:59:59.000Z'), now)).toBe('on_demand');
    expect(classifyBookingType(new Date('2026-06-02T13:00:00.000Z'), now)).toBe('on_demand');
  });

  test('normalizes tutor feedback and rejects incomplete feedback', () => {
    expect(normalizeTutorFeedback(null)).toBeNull();
    expect(normalizeTutorFeedback({ attendance: 'attended' })).toBeNull();
    expect(normalizeTutorFeedback({
      attendance: 'invalid',
      covered: 'Fractions and ratios',
      engagement: 'Focused',
      improvementSignal: 'Solved more independently',
      nextSteps: 'Practice equivalent fractions',
    })).toBeNull();

    expect(normalizeTutorFeedback({
      attendance: 'attended',
      covered: 'Fractions and ratios',
      engagement: 'Focused after warm-up',
      improvementSignal: 'Solved multi-step examples with fewer prompts',
      nextSteps: 'Practice equivalent fractions and word problems',
      supportConcern: ' ',
    })).toEqual({
      attendance: 'attended',
      covered: 'Fractions and ratios',
      engagement: 'Focused after warm-up',
      homework: '',
      improvementSignal: 'Solved multi-step examples with fewer prompts',
      nextSteps: 'Practice equivalent fractions and word problems',
      supportConcern: null,
    });
  });

  test('requires feedback, dispute clearance, and elapsed payout window before payout', () => {
    const now = new Date('2026-06-02T12:00:00.000Z');

    expect(getPayoutEligibility({
      sessionStatus: 'completed',
      payoutStatus: 'scheduled',
      payoutAt: '2026-06-02T11:59:00.000Z',
      tutorFeedbackSubmittedAt: null,
      hasOpenDispute: false,
      now,
    })).toEqual({ eligible: false, reason: 'missing_tutor_feedback' });

    expect(getPayoutEligibility({
      sessionStatus: 'completed',
      payoutStatus: 'scheduled',
      payoutAt: '2026-06-02T11:59:00.000Z',
      tutorFeedbackSubmittedAt: '2026-06-02T10:00:00.000Z',
      hasOpenDispute: true,
      now,
    })).toEqual({ eligible: false, reason: 'open_dispute' });

    expect(getPayoutEligibility({
      sessionStatus: 'completed',
      payoutStatus: 'scheduled',
      payoutAt: '2026-06-02T13:00:00.000Z',
      tutorFeedbackSubmittedAt: '2026-06-02T10:00:00.000Z',
      hasOpenDispute: false,
      now,
    })).toEqual({ eligible: false, reason: 'payout_window_not_elapsed' });

    expect(getPayoutEligibility({
      sessionStatus: 'completed',
      payoutStatus: 'scheduled',
      payoutAt: '2026-06-02T11:59:00.000Z',
      tutorFeedbackSubmittedAt: '2026-06-02T10:00:00.000Z',
      hasOpenDispute: false,
      now,
    })).toEqual({ eligible: true, reason: 'eligible' });
  });
});
