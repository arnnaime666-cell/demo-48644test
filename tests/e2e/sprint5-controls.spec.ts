import { expect, test } from '@playwright/test';

test.describe('Actual Sprint 5 control boundaries', () => {
  test('booking response requires an authenticated tutor', async ({ request }) => {
    const response = await request.post('/api/sessions/00000000-0000-0000-0000-000000000000/respond', {
      data: { action: 'accept' },
    });
    expect(response.status()).toBe(401);
  });

  test('admin account invitation requires an authenticated admin', async ({ request }) => {
    const response = await request.post('/api/admin/accounts', {
      data: {
        email: 'unauthorized@example.com',
        fullName: 'Unauthorized User',
        role: 'parent',
      },
    });
    expect(response.status()).toBe(401);
  });

  test('admin account lifecycle mutation requires an authenticated admin', async ({ request }) => {
    const response = await request.patch('/api/admin/accounts/00000000-0000-0000-0000-000000000000', {
      data: { action: 'reset_mfa' },
    });
    expect(response.status()).toBe(401);
  });

  test('session reminder worker never runs without cron authentication', async ({ request }) => {
    const response = await request.get('/api/cron/session-reminders');
    expect([401, 503]).toContain(response.status());
  });
});
