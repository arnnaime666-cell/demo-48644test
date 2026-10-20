import { expect, test } from '@playwright/test';
import { countReviewStates, normalizeReviewState } from '../../src/domains/admin/server/tutor-review-queue';
import { TUTOR_PROFILE_SELECT } from '../../src/lib/supabase/selects';
import { CURRENT_COMMISSION_VERSION, type TutorWithProfile } from '../../src/types';
import { getServiceSupabase } from './helpers/supabase';

function tutorFixture(overrides: Partial<TutorWithProfile>): TutorWithProfile {
  return {
    id: crypto.randomUUID(),
    bio: 'Experienced math tutor',
    subjects: ['Mathematics'],
    grade_levels: ['Grade 4'],
    curriculum_tags: [],
    languages: ['English'],
    intro_video_url: null,
    hourly_rate: 5000,
    session_duration: 60,
    commission_tier: 'starter',
    quality_status: 'good',
    quality_flagged_at: null,
    quality_review_notes: null,
    stripe_account_id: null,
    stripe_account_status: 'pending',
    application_status: 'pending',
    flagged_reasons: null,
    documents: {
      government_id: { url: 'https://example.com/id.pdf', status: 'uploaded' },
      teaching_certificate: { url: 'https://example.com/cert.pdf', status: 'uploaded' },
      degree: { url: 'https://example.com/degree.pdf', status: 'uploaded' },
      background_check: { url: 'https://example.com/check.pdf', status: 'uploaded' },
    },
    rejection_reason: null,
    rejection_reason_code: null,
    rejection_count: 0,
    rejected_at: null,
    can_reapply_at: null,
    senior_admin_id: null,
    is_active: false,
    rating_avg: 0,
    total_sessions: 0,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    profiles: {
      id: crypto.randomUUID(),
      email: 'review-queue@example.com',
      full_name: 'Review Queue Tutor',
      phone: null,
      avatar_url: null,
      role: 'tutor',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      province: 'Ontario',
      children_info: null,
      email_verified: true,
      email_confirmed_at: new Date().toISOString(),
      phone_verified: true,
      terms_accepted_at: new Date().toISOString(),
      terms_version: '2026-04-01',
      commission_accepted_at: new Date().toISOString(),
      commission_version: CURRENT_COMMISSION_VERSION,
      subscription_tier: null,
      subscription_status: 'inactive',
      stripe_customer_id: null,
      stripe_subscription_id: null,
    },
    ...overrides,
  };
}

test.describe('Admin tutor review queue', () => {
  test('normalizes incomplete pending tutor applications into the flagged review queue', () => {
    const pendingComplete = tutorFixture({});
    const pendingIncomplete = tutorFixture({
      bio: '',
      documents: {
        government_id: { url: null, status: 'pending' },
        teaching_certificate: { url: null, status: 'pending' },
        degree: { url: null, status: 'pending' },
        background_check: { url: null, status: 'pending' },
      },
    });

    expect(normalizeReviewState(pendingComplete).application_status).toBe('pending');
    expect(normalizeReviewState(pendingIncomplete)).toMatchObject({
      application_status: 'flagged',
      flagged_reasons: expect.arrayContaining([
        'bio',
        'government_id',
        'teaching_certificate',
        'degree',
        'background_check',
      ]),
    });

    expect(countReviewStates([pendingComplete, pendingIncomplete])).toMatchObject({
      pending: 1,
      flagged: 1,
      approved: 0,
      rejected: 0,
    });
  });

  test('uses an explicit tutor-to-profile relationship for Supabase embeds', async () => {
    expect(TUTOR_PROFILE_SELECT).toContain('profiles!tutors_id_fkey(*)');

    const supabase = getServiceSupabase();
    const { error } = await supabase
      .from('tutors')
      .select(TUTOR_PROFILE_SELECT)
      .in('application_status', ['pending', 'flagged'])
      .limit(1);

    expect(error).toBeNull();
  });
});
