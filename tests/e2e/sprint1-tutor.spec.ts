import { expect, test } from '@playwright/test';
import { cleanupUsersByEmail, getLatestOtpCode, getProfileByEmail, getTutorByEmail } from './helpers/supabase';
import { fillOtp, uniqueCanadianPhone, uniqueEmail } from './helpers/ui';

test.describe('Sprint 1 tutor onboarding', () => {
  test('completes tutor onboarding and flags missing required documents for admin review', async ({ page }) => {
    const email = uniqueEmail('e2e-tutor-complete');
    const phone = uniqueCanadianPhone();
    await cleanupUsersByEmail([email]);

    await page.goto('/signup/tutor');
    await page.getByLabel(/first name/i).fill('E2E');
    await page.getByLabel(/last name/i).fill('Tutor');
    await page.getByLabel(/email/i).fill(email);
    await page.getByLabel(/phone/i).fill(phone);
    await page.getByLabel(/^password$/i).fill('EducateED2026!');
    await page.getByLabel(/confirm password/i).fill('EducateED2026!');
    await page.getByRole('button', { name: /^next$/i }).click();

    await expect(page.getByText(/subjects & grade levels/i)).toBeVisible();
    await page.getByText('Mathematics', { exact: true }).click();
    await page.getByText('Grade 4', { exact: true }).click();
    await page.getByRole('button', { name: /^next$/i }).click();

    await expect(page.getByText(/bio & hourly rate/i)).toBeVisible();
    await page.getByLabel(/bio/i).fill('I am an experienced mathematics tutor who helps students build confidence through clear explanations and structured practice.');
    await page.getByLabel(/hourly rate/i).fill('55');
    await page.getByRole('button', { name: /next: verify email/i }).click();

    await fillOtp(page, await getLatestOtpCode(email, 'email'));
    await expect(page.getByText(/verify your phone/i)).toBeVisible();

    await fillOtp(page, await getLatestOtpCode(email, 'phone'));
    await expect(page.getByText('Terms & Commission', { exact: true })).toBeVisible();

    await page.getByLabel(/i have read and accept the/i).click();
    await expect(page.getByLabel(/i have read and accept the/i)).toBeChecked();
    await page.getByLabel(/i understand and accept the/i).click();
    await expect(page.getByLabel(/i understand and accept the/i)).toBeChecked();
    const validateResponsePromise = page.waitForResponse('**/api/tutor/validate-submission');
    await page.getByRole('button', { name: /submit application/i }).click();
    const validateResponse = await validateResponsePromise;
    expect(validateResponse.ok()).toBeTruthy();
    expect(await validateResponse.json()).toMatchObject({ status: 'flagged' });
    // Anchor the whole URL: a bare /\/tutor$/ also matches /signup/tutor, so it
    // passed while the wizard was still sitting on the terms step.
    await expect(page).toHaveURL(/^https?:\/\/[^/]+\/tutor$/);

    const profile = await getProfileByEmail(email);
    expect(profile).toMatchObject({
      role: 'tutor',
      email_verified: true,
      phone_verified: true,
    });
    expect(profile?.terms_accepted_at).toBeTruthy();
    expect(profile?.commission_accepted_at).toBeTruthy();

    const tutor = await getTutorByEmail(email);
    expect(tutor).toMatchObject({
      application_status: 'flagged',
      hourly_rate: 5500,
    });
    expect(tutor?.flagged_reasons).toEqual(
      expect.arrayContaining(['government_id', 'teaching_certificate', 'degree', 'background_check'])
    );

    await cleanupUsersByEmail([email]);
  });
});
