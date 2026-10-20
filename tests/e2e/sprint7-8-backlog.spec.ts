import { expect, test } from '@playwright/test';

/**
 * Auth boundaries for the Sprint 6–8 backlog endpoints built in this pass
 * (PAR-013 issue reports, ADM-013 financial reports, ADM-014 PIPEDA
 * export/deletion, TUT-019 tutor analytics).
 *
 * Follows the pattern of tests/e2e/sprint6-backlog.spec.ts: boundary-only
 * checks that never create data, so no fixtures or cleanup are needed even
 * though CI runs against the production database.
 */
const NIL_UUID = '00000000-0000-0000-0000-000000000000';

test.describe('Sprint 7-8 backlog control boundaries', () => {
  // PAR-013: in-session issue reports
  test('session issue reporting requires an authenticated participant', async ({ request }) => {
    const response = await request.post(`/api/sessions/${NIL_UUID}/report-issue`, {
      data: { category: 'technical', description: 'Audio kept dropping mid-lesson.' },
    });
    expect(response.status()).toBe(401);
  });

  // ADM-013: period financial reports
  test('financial period report requires an authenticated admin', async ({ request }) => {
    const response = await request.get('/api/admin/reports/financial');
    expect(response.status()).toBe(401);
  });

  test('financial period report CSV export requires an authenticated admin', async ({ request }) => {
    const response = await request.get('/api/admin/reports/financial?format=csv&from=2026-01-01');
    expect(response.status()).toBe(401);
  });

  // ADM-014: PIPEDA export & deletion requests
  test('PIPEDA data export requires an authenticated admin', async ({ request }) => {
    const response = await request.get(`/api/admin/accounts/${NIL_UUID}/export`);
    expect(response.status()).toBe(401);
  });

  test('deletion request intake requires authentication', async ({ request }) => {
    const response = await request.post('/api/account/deletion-request', {
      data: { reason: 'Please delete my account.' },
    });
    expect(response.status()).toBe(401);
  });

  test('deletion request listing requires authentication', async ({ request }) => {
    const response = await request.get('/api/account/deletion-request');
    expect(response.status()).toBe(401);
  });

  test('privacy request queue requires an authenticated admin', async ({ request }) => {
    const response = await request.get('/api/admin/privacy/requests');
    expect(response.status()).toBe(401);
  });

  test('processing a privacy request requires an authenticated admin', async ({ request }) => {
    const response = await request.patch(`/api/admin/privacy/requests/${NIL_UUID}`, {
      data: { action: 'process' },
    });
    expect(response.status()).toBe(401);
  });

  test('admin privacy page redirects unauthenticated visitors to login', async ({ page }) => {
    await page.goto('/admin/privacy');
    await expect(page).toHaveURL(/\/login/);
  });

  // TUT-019: tutor performance analytics
  test('tutor analytics page redirects unauthenticated visitors to login', async ({ page }) => {
    await page.goto('/tutor/analytics');
    await expect(page).toHaveURL(/\/login/);
  });
});
