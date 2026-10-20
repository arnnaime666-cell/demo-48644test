locals {
  app_domain = "educateed.ca"

  vercel_environment_inventory = {
    production = [
      "CRON_SECRET",
      "DAILY_API_KEY",
      "NEXT_PUBLIC_APP_URL",
      "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY",
      "NEXT_PUBLIC_SUPABASE_ANON_KEY",
      "NEXT_PUBLIC_SUPABASE_URL",
      "RESEND_API_KEY",
      "SENIOR_ADMIN_EMAILS",
      "SMS_PROVIDER",
      "STRIPE_SECRET_KEY",
      "STRIPE_WEBHOOK_SECRET",
      "SUPABASE_SERVICE_ROLE_KEY",
      "TELNYX_API_KEY",
      "TELNYX_PHONE_NUMBER",
      "TWILIO_ACCOUNT_SID",
      "TWILIO_AUTH_TOKEN",
      "TWILIO_PHONE_NUMBER"
    ]

    development = [
      "CRON_SECRET",
      "NEXT_PUBLIC_SUPABASE_ANON_KEY",
      "NEXT_PUBLIC_SUPABASE_URL",
      "SENIOR_ADMIN_EMAILS",
      "SUPABASE_SERVICE_ROLE_KEY"
    ]
  }
}

