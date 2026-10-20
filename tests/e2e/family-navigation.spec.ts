import { expect, test } from '@playwright/test';
import { CURRENT_COMMISSION_VERSION } from '../../src/types';
import { cleanupUsersByEmail, getProfileByEmail, getServiceSupabase } from './helpers/supabase';
import { uniqueCanadianPhone, uniqueEmail } from './helpers/ui';

const PASSWORD = 'EducateED2026!';

async function createVerifiedParent(email: string, phone: string) {
  const signupRes = await fetch(`${process.env.E2E_BASE_URL ?? 'http://127.0.0.1:3000'}/api/auth/e2e-signup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email,
      password: PASSWORD,
      fullName: 'Family Nav E2E',
      role: 'parent',
      phone,
      province: 'Ontario',
    }),
  });
  if (!signupRes.ok) {
    throw new Error(`e2e-signup failed: ${signupRes.status} ${await signupRes.text()}`);
  }
  const { userId } = (await signupRes.json()) as { userId: string };

  const supabase = getServiceSupabase();
  const { error } = await supabase
    .from('profiles')
    .update({
      email_verified: true,
      phone_verified: true,
      terms_accepted_at: new Date().toISOString(),
      terms_version: '2026-04-01',
      children_info: [
        { name: 'Test Child', grade: 'Grade 4', subjects: ['Mathematics'], preferredLanguage: 'English' },
      ],
    })
    .eq('id', userId);
  if (error) throw error;
  return userId;
}

test.describe('Family dashboard navigation', () => {
  test('verified parent can reach Find a Tutor from the dashboard card', async ({ page }) => {
    const email = uniqueEmail('e2e-fam-nav-card');
    const phone = uniqueCanadianPhone();
    await cleanupUsersByEmail([email]);
    await createVerifiedParent(email, phone);

    try {
      await page.goto('/login');
      await page.getByLabel(/email/i).fill(email);
      await page.getByLabel(/password/i).fill(PASSWORD);
      await page.getByRole('button', { name: /sign in/i }).click();

      await expect(page).toHaveURL(/\/family$/);
      await expect(page.getByRole('heading', { name: /family dashboard/i })).toBeVisible();

      // Click the "Find a Tutor" card link
      await page.locator('a[href="/family/find"]').filter({ hasText: /browse qualified/i }).click();
      await expect(page).toHaveURL(/\/family\/find$/, { timeout: 15_000 });
      await expect(page.getByRole('heading', { name: /find a tutor/i })).toBeVisible();
    } finally {
      await cleanupUsersByEmail([email]);
    }
  });

  test('verified parent can reach Find Tutors from the sidebar', async ({ page }) => {
    const email = uniqueEmail('e2e-fam-nav-side');
    const phone = uniqueCanadianPhone();
    await cleanupUsersByEmail([email]);
    await createVerifiedParent(email, phone);

    try {
      await page.goto('/login');
      await page.getByLabel(/email/i).fill(email);
      await page.getByLabel(/password/i).fill(PASSWORD);
      await page.getByRole('button', { name: /sign in/i }).click();
      await expect(page).toHaveURL(/\/family$/);

      await page.getByRole('link', { name: /find tutors/i }).click();
      await expect(page).toHaveURL(/\/family\/find$/, { timeout: 15_000 });
    } finally {
      await cleanupUsersByEmail([email]);
    }
  });

  test('verified parent does NOT bounce back to login when visiting /family/find', async ({ page }) => {
    const email = uniqueEmail('e2e-fam-nav-direct');
    const phone = uniqueCanadianPhone();
    await cleanupUsersByEmail([email]);
    await createVerifiedParent(email, phone);

    try {
      await page.goto('/login');
      await page.getByLabel(/email/i).fill(email);
      await page.getByLabel(/password/i).fill(PASSWORD);
      await page.getByRole('button', { name: /sign in/i }).click();
      await expect(page).toHaveURL(/\/family$/);

      await page.goto('/family/find');
      await expect(page).toHaveURL(/\/family\/find$/);
      await expect(page).not.toHaveURL(/\/login/);
      await expect(page.getByRole('heading', { name: /find a tutor/i })).toBeVisible();
    } finally {
      await cleanupUsersByEmail([email]);
    }
  });

  test('tutor accessing /family/find is redirected to tutor dashboard', async ({ page }) => {
    const email = uniqueEmail('e2e-fam-nav-tutor');
    const phone = uniqueCanadianPhone();
    await cleanupUsersByEmail([email]);

    const baseUrl = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:3000';
    const signupRes = await fetch(`${baseUrl}/api/auth/e2e-signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password: PASSWORD,
        fullName: 'Tutor Nav E2E',
        role: 'tutor',
        phone,
        province: 'Ontario',
      }),
    });
    const { userId } = (await signupRes.json()) as { userId: string };

    const supabase = getServiceSupabase();
    await supabase
      .from('profiles')
      .update({
        email_verified: true,
        phone_verified: true,
        terms_accepted_at: new Date().toISOString(),
        terms_version: '2026-04-01',
        commission_accepted_at: new Date().toISOString(),
        commission_version: CURRENT_COMMISSION_VERSION,
      })
      .eq('id', userId);
    await supabase.from('tutors').upsert({ id: userId }, { onConflict: 'id' });

    try {
      await page.goto('/login');
      await page.getByLabel(/email/i).fill(email);
      await page.getByLabel(/password/i).fill(PASSWORD);
      await page.getByRole('button', { name: /sign in/i }).click();
      await expect(page).toHaveURL(/\/tutor$/);

      // A tutor hitting a family route is redirected server-side to /tutor.
      // page.goto rejects with net::ERR_ABORTED when the redirect interrupts
      // the document load — that abort IS the redirect firing, not a failure,
      // so swallow it and assert the destination. A real crash would still be
      // caught: the URL would not become /tutor.
      await page.goto('/family/find').catch(() => {});
      await expect(page).toHaveURL(/\/tutor$/, { timeout: 15_000 });
    } finally {
      await cleanupUsersByEmail([email]);
    }
  });

  test('tutor result card actions route to the matching profile and booking pages', async ({ page }) => {
    const parentEmail = uniqueEmail('e2e-fam-card-actions-parent');
    const tutorEmail = uniqueEmail('e2e-fam-card-actions-tutor');
    const parentPhone = uniqueCanadianPhone();
    const tutorPhone = uniqueCanadianPhone();
    await cleanupUsersByEmail([parentEmail, tutorEmail]);

    const tutorName = `Tutor Card Actions ${tutorEmail}`;
    const tutorBio = 'I am an experienced mathematics tutor who helps students build confidence through clear explanations and structured practice.';
    await createVerifiedParent(parentEmail, parentPhone);

    const baseUrl = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:3000';
    const tutorSignupRes = await fetch(`${baseUrl}/api/auth/e2e-signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: tutorEmail,
        password: PASSWORD,
        fullName: tutorName,
        role: 'tutor',
        phone: tutorPhone,
        province: 'Ontario',
      }),
    });
    if (!tutorSignupRes.ok) {
      throw new Error(`tutor e2e-signup failed: ${tutorSignupRes.status} ${await tutorSignupRes.text()}`);
    }
    const { userId: tutorId } = (await tutorSignupRes.json()) as { userId: string };

    const supabase = getServiceSupabase();
    const parentProfile = await getProfileByEmail(parentEmail);
    if (!parentProfile) throw new Error('Expected parent profile to exist');

    await supabase
      .from('profiles')
      .update({
        subscription_tier: 'basic',
        subscription_status: 'active',
      })
      .eq('id', parentProfile.id);
    await supabase
      .from('profiles')
      .update({
        email_verified: true,
        phone_verified: true,
        terms_accepted_at: new Date().toISOString(),
        terms_version: '2026-04-01',
        commission_accepted_at: new Date().toISOString(),
        commission_version: CURRENT_COMMISSION_VERSION,
      })
      .eq('id', tutorId);
    await supabase
      .from('tutors')
      .upsert({
        id: tutorId,
        bio: tutorBio,
        subjects: ['Mathematics'],
        grade_levels: ['Grade 4'],
        languages: ['English'],
        hourly_rate: 5500,
        session_duration: 60,
        application_status: 'approved',
        quality_status: 'good',
        is_active: true,
      }, { onConflict: 'id' });

    try {
      await page.goto('/login');
      await page.getByLabel(/email/i).fill(parentEmail);
      await page.getByLabel(/password/i).fill(PASSWORD);
      await page.getByRole('button', { name: /sign in/i }).click();
      await expect(page).toHaveURL(/\/family$/);

      await page.goto('/family/find');
      const tutorCard = page.locator('[data-testid="tutor-card"]').filter({ hasText: tutorName });
      await expect(tutorCard).toBeVisible();

      await tutorCard.getByRole('link', { name: /profile/i }).click();
      await expect(page).toHaveURL(new RegExp(`/family/tutors/${tutorId}$`), { timeout: 15_000 });
      await expect(page.getByRole('heading', { name: tutorName })).toBeVisible();

      await page.goto('/family/find');
      await tutorCard.getByRole('link', { name: /book a session/i }).click();
      await expect(page).toHaveURL(new RegExp(`/family/book/${tutorId}$`), { timeout: 15_000 });
      await expect(page.getByRole('heading', { name: /book a session/i })).toBeVisible();
      await expect(page.getByText(tutorName).first()).toBeVisible();

      expect(page.url()).not.toContain(`/family/tutors/${parentProfile.id}`);
      expect(page.url()).not.toContain('/family/profile');
    } finally {
      await cleanupUsersByEmail([parentEmail, tutorEmail]);
    }
  });

  test('default Basic parent can book without a subscription', async ({ page }) => {
    const parentEmail = uniqueEmail('e2e-fam-card-actions-basic-parent');
    const tutorEmail = uniqueEmail('e2e-fam-card-actions-basic-tutor');
    await cleanupUsersByEmail([parentEmail, tutorEmail]);

    const tutorName = `Basic Parent Booking ${tutorEmail}`;
    await createVerifiedParent(parentEmail, uniqueCanadianPhone());

    const baseUrl = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:3000';
    const tutorSignupRes = await fetch(`${baseUrl}/api/auth/e2e-signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: tutorEmail,
        password: PASSWORD,
        fullName: tutorName,
        role: 'tutor',
        phone: uniqueCanadianPhone(),
        province: 'Ontario',
      }),
    });
    if (!tutorSignupRes.ok) {
      throw new Error(`tutor e2e-signup failed: ${tutorSignupRes.status} ${await tutorSignupRes.text()}`);
    }
    const { userId: tutorId } = (await tutorSignupRes.json()) as { userId: string };

    const supabase = getServiceSupabase();
    await supabase
      .from('profiles')
      .update({
        email_verified: true,
        phone_verified: true,
        terms_accepted_at: new Date().toISOString(),
        terms_version: '2026-04-01',
        commission_accepted_at: new Date().toISOString(),
        commission_version: CURRENT_COMMISSION_VERSION,
      })
      .eq('id', tutorId);
    await supabase
      .from('tutors')
      .upsert({
        id: tutorId,
        bio: 'I am an experienced mathematics tutor who helps students build confidence through clear explanations and structured practice.',
        subjects: ['Mathematics'],
        grade_levels: ['Grade 4'],
        languages: ['English'],
        hourly_rate: 5500,
        session_duration: 60,
        application_status: 'approved',
        quality_status: 'good',
        is_active: true,
      }, { onConflict: 'id' });

    try {
      await page.goto('/login');
      await page.getByLabel(/email/i).fill(parentEmail);
      await page.getByLabel(/password/i).fill(PASSWORD);
      await page.getByRole('button', { name: /sign in/i }).click();
      await expect(page).toHaveURL(/\/family$/);

      await page.goto('/family/find?province=Alberta');
      await expect(page.getByTestId('service-area-filter')).toHaveText('Ontario');
      await expect(page.getByText(/all provinces/i)).toHaveCount(0);
      const tutorCard = page.locator('[data-testid="tutor-card"]').filter({ hasText: tutorName });
      await expect(tutorCard).toBeVisible();
      await expect(tutorCard.getByRole('link', { name: /profile/i })).toHaveAttribute('href', `/family/tutors/${tutorId}`);
      await expect(tutorCard.getByRole('link', { name: /book a session/i })).toHaveAttribute('href', `/family/book/${tutorId}`);
    } finally {
      await cleanupUsersByEmail([parentEmail, tutorEmail]);
    }
  });
});
