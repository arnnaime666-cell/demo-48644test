# Stripe Setup Checklist — PAY-001

Step-by-step guide to configuring Stripe for EducateED session checkout, subscriptions, tutor Connect onboarding, webhook handling, and go-live.

## Current Production Status

- [x] Stripe account is live and business verification is submitted.
- [x] Charges, payouts, and transfers are enabled on the platform account.
- [x] Production webhook endpoint exists: `https://educateed.ca/api/stripe/webhook`
- [x] Production `STRIPE_WEBHOOK_SECRET` has been updated in Vercel.
- [x] Live Premium price exists at `$29.99 CAD/month` on the `EducateED Premium` product.
- [x] Production `STRIPE_PREMIUM_PRICE_ID` points to the `$29.99 CAD/month` Premium price.
- [ ] Stripe Connect platform signup still must be completed in the Stripe Dashboard.

Stripe currently blocks Express connected account creation until Connect signup is completed in Dashboard. The app code is already prepared for Express Connect onboarding once that gate is cleared.

Recommended Connect setup choices:

- Platform type: marketplace
- Connected account type: Express
- Platform country/currency: Canada / CAD
- Funds flow: families pay EducateED; EducateED later transfers tutor payouts
- Integration pattern: separate charges and transfers
- Connected account users: individual tutors

---

## 1. Stripe Account Setup

- [ ] Create a Stripe account at [dashboard.stripe.com/register](https://dashboard.stripe.com/register)
- [ ] Complete business verification (Stripe will request):
  - Legal entity name and type
  - Business registration number (Canada)
  - Business address (Canada)
  - Directors/owners with ID verification
- [ ] Enable **Canada** as the primary country and **CAD** as the default currency
- [ ] Enable **USD** as a secondary currency if cross-border payments are expected
- [ ] Set payout schedule: daily or weekly (recommend weekly during early launch)
- [ ] Add team members with appropriate Dashboard roles if multiple people need access

> **Note:** Stripe verification can take 1–3 business days. Start this early.

---

## 2. Product & Price Creation

Create one subscription product in the Stripe Dashboard under **Products → Add product**.

### Basic Plan

Basic is included with every Parent/Student account. Do not create a Stripe product or Price ID for Basic.

Included Basic access:

- Access to Parent/Student account
- Access to provide feedback
- Book a session
- Join a session

### Premium Plan

| Field | Value |
|-------|-------|
| Name | EducateED Premium |
| Description | Premium learning support features |
| Pricing model | Recurring |
| Price | $29.99 CAD/month |
| Billing period | Monthly |
| Tax | Enable if applicable (GST/HST) |

### After Creation

- [ ] Copy the **Price ID** for Premium (starts with `price_...`) → this becomes `STRIPE_PREMIUM_PRICE_ID`
- [ ] Record the Premium Price ID — you'll need it in environment variables below

> Basic does not need a Stripe product. It is the default access level for parent accounts.

---

## 3. Webhook Configuration

### Endpoint Setup

In the Stripe Dashboard, go to **Developers → Webhooks → Add endpoint**.

| Setting | Value |
|---------|-------|
| Endpoint URL | `https://your-domain.com/api/stripe/webhook` |
| Description | EducateED webhook listener |

### Events to Subscribe

Select these events (minimum required for subscription flow):

- [ ] `customer.subscription.created`
- [ ] `customer.subscription.updated`
- [ ] `customer.subscription.deleted`
- [ ] `invoice.paid`
- [ ] `invoice.payment_failed`
- [ ] `payment_intent.succeeded` *(already handled — see `stripe-webhooks.ts`)*
- [ ] `payment_intent.payment_failed`
- [ ] `payment_intent.canceled`
- [ ] `refund.created`
- [ ] `refund.updated`
- [ ] `checkout.session.expired`
- [ ] `account.updated` *(already handled — Stripe Connect)*
- [ ] `transfer.created` *(already handled — Stripe Connect)*

> The webhook handler at `src/app/api/stripe/webhook/route.ts` processes session payments, tutor Stripe Connect updates, transfer events, and subscription billing events. For Sprint 2 paid plans, make sure `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, and `invoice.payment_failed` are enabled in Stripe.

### After Creation

- [ ] Copy the **Signing secret** (starts with `whsec_...`) → this becomes `STRIPE_WEBHOOK_SECRET`
- [ ] For local development, use the Stripe CLI (see section 5)

### Local Webhook Testing with Stripe CLI

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login (opens browser)
stripe login

# Forward webhooks to local dev server
stripe listen --forward-to localhost:3000/api/stripe/webhook

# The CLI prints a whsec_... key — use that as STRIPE_WEBHOOK_SECRET in .env.local
```

---

## 4. Environment Variables

### Local Development (`.env.local`)

```env
# Stripe — Core
STRIPE_SECRET_KEY=sk_test_...
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...

# Stripe — Subscriptions (PAY-001)
STRIPE_PREMIUM_PRICE_ID=price_...

# Stripe — Webhooks
STRIPE_WEBHOOK_SECRET=whsec_...
```

### Production (Vercel Environment Variables)

Set the same variables in **Vercel Dashboard → Settings → Environment Variables**, but use **live** keys:

```env
STRIPE_SECRET_KEY=sk_live_...
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_PREMIUM_PRICE_ID=price_...   # live-mode Premium Price ID
STRIPE_WEBHOOK_SECRET=whsec_...     # from the live-mode webhook endpoint
```

> **Important:** Price IDs are mode-specific. If you create prices in test mode, you must recreate them in live mode and use the live-mode Price IDs in production.

### Current State in Repo

| Variable | Status |
|----------|--------|
| `STRIPE_SECRET_KEY` | ✅ Set in `.env.local` (test key) |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | ✅ Set in `.env.local` (test key) |
| `STRIPE_WEBHOOK_SECRET` | ✅ Set in `.env.local` |
| `STRIPE_PREMIUM_PRICE_ID` | ❌ Not yet set |

---

## 5. Testing Checklist

### Stripe Test Cards

| Card Number | Result |
|-------------|--------|
| `4242 4242 4242 4242` | Succeeds |
| `4000 0025 0000 3155` | Requires authentication (3D Secure) |
| `4000 0000 0000 0002` | Declines |
| `4000 0000 0000 3220` | 3D Secure required |

Use any future expiry date, any CVC, and any postal code.

### Subscription Flow Tests

- [ ] **Basic access**: Create a parent account and verify it can book, join sessions, and provide feedback without Stripe checkout
- [ ] **Create subscription — Premium**: Subscribe with test card `4242...4242`, verify subscription created in Stripe Dashboard, verify database updated
- [ ] **Subscription renewal**: Wait for invoice or trigger via Dashboard, verify `invoice.paid` webhook fires and handler processes it
- [ ] **Payment failure**: Use card `4000...0002`, verify `invoice.payment_failed` webhook fires, subscription marked as past_due or canceled
- [ ] **Subscription cancel**: Cancel via Dashboard or API, verify `customer.subscription.deleted` fires and user returns to Basic access
- [ ] **3D Secure**: Use card `4000...3155`, complete 3DS challenge, verify payment succeeds
- [ ] **Webhook delivery**: Check Stripe Dashboard → Webhooks → endpoint logs for successful deliveries (200 status)
- [ ] **Webhook signature**: Confirm invalid signatures are rejected by `stripe-webhooks.ts` handler (returns 400)

### Session Payment Regression Tests

Single-session payment flows must work through Stripe Payment Intents:

- [ ] Book a single session as a Basic user → `payment_intent.succeeded` fires, payment becomes held and tutor receives a request
- [ ] Tutor accepts → session confirms and room is provisioned
- [ ] Tutor declines → idempotent Stripe refund and cancelled session
- [ ] Cancel a fully refundable paid session → Stripe refund is issued against `stripe_payment_intent_id`
- [ ] Tutor Stripe Connect onboarding still works (`account.updated` fires)
- [ ] Transfer to tutor after session completes (`transfer.created` fires)

---

## 6. Production Go-Live

### Pre-Launch

- [ ] Complete Stripe account verification (all business details confirmed)
- [ ] Switch Stripe Dashboard from **Test** to **Live** mode
- [ ] Create the Premium product/price in **live** mode
- [ ] Set up live-mode webhook endpoint with signing secret
- [ ] Update Vercel environment variables with live keys and live Price IDs
- [ ] Remove any hardcoded test keys from code or config
- [ ] Verify `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` is `pk_live_...` in production
- [ ] Verify `STRIPE_SECRET_KEY` is `sk_live_...` in production
- [ ] Confirm webhook endpoint URL points to production domain (not localhost)

### Post-Launch Verification

- [ ] Make a real test purchase with a real card
- [ ] Confirm subscription appears in Stripe Dashboard → Customers
- [ ] Confirm webhook events deliver successfully (check Dashboard → Webhooks → logs)
- [ ] Confirm invoice receipt email sends (if configured)
- [ ] Monitor first 24h for failed payments or webhook errors
- [ ] Set up Stripe Dashboard alerts for failed payments and disputes

### Security Checklist

- [ ] `STRIPE_SECRET_KEY` is server-only (never exposed to client)
- [ ] `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` is the only Stripe key on the client
- [ ] Webhook signature verification is enabled (already in `route.ts`)
- [ ] No test keys in production environment
- [ ] Rate limiting on `/api/stripe/checkout` and `/api/stripe/webhook` endpoints

---

## Quick Reference

| Resource | URL |
|----------|-----|
| Stripe Dashboard | [dashboard.stripe.com](https://dashboard.stripe.com) |
| Stripe API Docs | [docs.stripe.com/api](https://docs.stripe.com/api) |
| Stripe CLI | [github.com/stripe/stripe-cli](https://github.com/stripe/stripe-cli) |
| Test Card Numbers | [docs.stripe.com/testing](https://docs.stripe.com/testing) |
| Webhook Events | [docs.stripe.com/webhooks](https://docs.stripe.com/webhooks) |

---

*Last updated: 2026-05-27 — Sprint 2, PAY-001*
