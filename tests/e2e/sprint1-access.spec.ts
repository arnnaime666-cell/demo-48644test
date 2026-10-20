import { expect, test } from '@playwright/test';

test.describe('Sprint 1 access rules', () => {
  test('public homepage and FAQ are accessible without authentication', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL('/');
    await expect(page.locator('body')).toContainText(/EducateED/i);

    await page.goto('/faq');
    await expect(page).toHaveURL('/faq');
    await expect(page.locator('body')).toContainText(/FAQ|question|tutor/i);
  });

  for (const protectedPath of ['/admin', '/family', '/tutor', '/student', '/session/e2e-placeholder']) {
    test(`redirects unauthenticated users from ${protectedPath} to login`, async ({ page }, testInfo) => {
      await page.goto(protectedPath);
      await expect(page).toHaveURL(new RegExp(`/login\\?next=${encodeURIComponent(protectedPath)}$`));
      await expect(page.getByText(/sign in to your account/i)).toBeVisible();
      testInfo.annotations.push({ type: 'protected-path', description: protectedPath });
    });
  }

  test('public homepage Find a Tutor CTA starts parent signup instead of a login bounce', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('link', { name: /^find a tutor$/i }).first().click();
    await expect(page).toHaveURL(/\/signup\/parent$/);
    await expect(page.getByText(/create a parent account/i)).toBeVisible();
  });
});
