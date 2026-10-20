import { expect, test } from '@playwright/test';

/**
 * Auth boundaries for the Sprint 5/6 backlog endpoints
 * (ADM-011 analytics, ADM-012 bulk ops + CSV export).
 * Follows the pattern of sprint5-controls.spec.ts.
 */
test.describe('Sprint 6 backlog control boundaries', () => {
  test('tutor CSV export requires an authenticated admin', async ({ request }) => {
    const response = await request.get('/api/admin/tutors/export');
    expect(response.status()).toBe(401);
  });

  test('bulk tutor operations require an authenticated admin', async ({ request }) => {
    const response = await request.post('/api/admin/tutors/bulk', {
      data: {
        action: 'restore',
        tutorIds: ['00000000-0000-0000-0000-000000000000'],
      },
    });
    expect(response.status()).toBe(401);
  });

  test('bulk tutor operations reject malformed payloads before any work', async ({
    request,
  }) => {
    const response = await request.post('/api/admin/tutors/bulk', {
      data: { action: 'delete', tutorIds: [] },
    });
    expect(response.status()).toBe(400);
  });

  test('admin analytics page redirects unauthenticated visitors to login', async ({ page }) => {
    await page.goto('/admin/analytics');
    await expect(page).toHaveURL(/\/login/);
  });

  // PAR-011: learning goals and progress tracking
  test('learning goal creation requires an authenticated family account', async ({ request }) => {
    const response = await request.post('/api/family/goals', {
      data: { subject: 'Mathematics', title: 'Master fractions' },
    });
    expect(response.status()).toBe(401);
  });

  test('learning goal mutation requires an authenticated family account', async ({ request }) => {
    const response = await request.patch(
      '/api/family/goals/00000000-0000-0000-0000-000000000000',
      { data: { status: 'achieved' } }
    );
    expect(response.status()).toBe(401);
  });

  test('learning goal payloads are validated before any data access', async ({ request }) => {
    const response = await request.post('/api/family/goals', {
      data: { subject: 'Alchemy', title: 'x' },
    });
    expect(response.status()).toBe(400);
  });

  test('family progress page redirects unauthenticated visitors to login', async ({ page }) => {
    await page.goto('/family/progress');
    await expect(page).toHaveURL(/\/login/);
  });

  // PAR-010: session recording consent + retention
  test('recording consent requires an authenticated participant', async ({ request }) => {
    const response = await request.post(
      '/api/sessions/00000000-0000-0000-0000-000000000000/recording-consent',
      { data: { consent: true } }
    );
    expect(response.status()).toBe(401);
  });

  test('recording retention worker never runs without cron authentication', async ({
    request,
  }) => {
    const response = await request.get('/api/cron/recording-retention');
    expect([401, 503]).toContain(response.status());
  });

  // PAY-003: token packages are a feature-flagged scaffold only
  test('token package purchase is not implemented', async ({ request }) => {
    const response = await request.post('/api/payments/token-packages', { data: {} });
    expect(response.status()).toBe(501);
  });

  test('token package catalog requires authentication', async ({ request }) => {
    const response = await request.get('/api/payments/token-packages');
    expect(response.status()).toBe(401);
  });
});
