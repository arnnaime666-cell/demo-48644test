import { expect, test } from '@playwright/test';

test.describe('Sprint 2 API access rules', () => {
  test('requires authentication for subscription and invoice APIs', async ({ request }) => {
    const subscriptionGet = await request.get('/api/payments/subscription');
    expect(subscriptionGet.status()).toBe(401);

    const subscriptionPost = await request.post('/api/payments/subscription', {
      data: { tier: 'basic' },
    });
    expect(subscriptionPost.status()).toBe(401);

    const invoicePost = await request.post('/api/payments/invoice', {
      data: { sessionId: '00000000-0000-0000-0000-000000000000' },
    });
    expect(invoicePost.status()).toBe(401);
  });

  test('protects the reapplication cron endpoint', async ({ request }) => {
    const response = await request.get('/api/cron/reapplication-check');
    expect([401, 503]).toContain(response.status());
  });
});
