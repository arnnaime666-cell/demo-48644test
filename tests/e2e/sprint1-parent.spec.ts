import { expect, test } from '@playwright/test';
import { cleanupUsersByEmail, getLatestOtpCode, getProfileByEmail } from './helpers/supabase';
import { fillOtp, uniqueCanadianPhone, uniqueEmail } from './helpers/ui';

test.describe('Sprint 1 parent onboarding', () => {
  test('redirects /signup to the parent signup flow', async ({ page }) => {
    await page.goto('/signup');
    await expect(page).toHaveURL(/\/signup\/parent$/);
    await expect(page.getByText(/create a parent account/i)).toBeVisible();
  });

  test('keeps an incomplete parent signup out of the family dashboard', async ({ page }) => {
    const email = uniqueEmail('e2e-parent-guard');
    const phone = uniqueCanadianPhone();
    await cleanupUsersByEmail([email]);

    await page.goto('/signup/parent');
    await page.getByLabel(/full name/i).fill('E2E Parent Guard');
    await page.getByLabel(/email/i).fill(email);
    await page.getByLabel(/phone/i).fill(phone);
    await page.locator('#province').selectOption('Ontario');
    await page.getByLabel(/^password$/i).fill('EducateED2026!');
    await page.getByLabel(/confirm password/i).fill('EducateED2026!');
    await page.getByRole('button', { name: /next: children's info/i }).click();

    await expect(page.getByText(/your children/i)).toBeVisible();

    await page.goto('/family');
    await expect(page).toHaveURL(/\/login\?next=%2Ffamily$/);
    await expect(page.getByText(/sign in to your account/i)).toBeVisible();

    await cleanupUsersByEmail([email]);
  });

  test('completes parent signup with child preferences, email OTP, SMS OTP, and terms', async ({ page }) => {
    const email = uniqueEmail('e2e-parent-complete');
    const phone = uniqueCanadianPhone();
    await cleanupUsersByEmail([email]);

    await page.goto('/signup/parent');
    await page.getByLabel(/full name/i).fill('E2E Parent Complete');
    await page.getByLabel(/email/i).fill(email);
    await page.getByLabel(/phone/i).fill(phone);
    await page.locator('#province').selectOption('Ontario');
    await page.getByLabel(/^password$/i).fill('EducateED2026!');
    await page.getByLabel(/confirm password/i).fill('EducateED2026!');
    await page.getByRole('button', { name: /next: children's info/i }).click();

    await page.getByPlaceholder(/child's first name/i).fill('Jamie');
    await page.getByText('Select grade').click();
    await page.getByRole('option', { name: 'Grade 4' }).click();
    await page.getByRole('button', { name: 'Mathematics' }).click();
    await page.getByText('Select language').click();
    await page.getByRole('option', { name: 'English' }).click();
    await page.getByRole('button', { name: /next: verify email/i }).click();

    await fillOtp(page, await getLatestOtpCode(email, 'email'));
    await expect(page.getByText(/verify your phone/i)).toBeVisible();

    await fillOtp(page, await getLatestOtpCode(email, 'phone'));
    await expect(page.getByText(/terms & conditions/i)).toBeVisible();

    await page.getByLabel(/i have read and accept/i).click();
    await expect(page.getByLabel(/i have read and accept/i)).toBeChecked();
    await page.getByRole('button', { name: /finish signup/i }).click();
    await expect(page).toHaveURL(/\/family$/);

    const profile = await getProfileByEmail(email);
    expect(profile).toMatchObject({
      role: 'parent',
      province: 'Ontario',
      email_verified: true,
      phone_verified: true,
    });
    expect(profile?.children_info?.[0]).toMatchObject({
      name: 'Jamie',
      grade: 'Grade 4',
      preferredLanguage: 'English',
    });
    expect(profile?.children_info?.[0]?.subjects).toContain('Mathematics');

    await cleanupUsersByEmail([email]);
  });
});
