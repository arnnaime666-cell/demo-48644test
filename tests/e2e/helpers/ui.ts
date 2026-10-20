import { expect, type Page } from '@playwright/test';

export async function fillOtp(page: Page, code: string) {
  const inputs = page.locator('input[inputmode="numeric"]');
  await expect(inputs).toHaveCount(6);
  for (let i = 0; i < code.length; i += 1) {
    await inputs.nth(i).fill(code[i]);
  }
}

export async function selectRadixOption(page: Page, triggerName: string | RegExp, optionName: string | RegExp) {
  await page.getByRole('combobox', { name: triggerName }).click();
  await page.getByRole('option', { name: optionName }).click();
}

export function uniqueEmail(prefix: string) {
  return `${prefix}+${Date.now()}-${Math.random().toString(16).slice(2)}@example.com`;
}

export function uniqueCanadianPhone() {
  const suffix = String(Date.now() % 10_000).padStart(4, '0');
  return `+1 (416) 555-${suffix}`;
}
