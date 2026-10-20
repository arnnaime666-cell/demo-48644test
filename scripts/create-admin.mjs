import { createClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
const fullName = process.env.ADMIN_FULL_NAME || 'EducateED Admin';

if (!url || !serviceRoleKey || !email || !password) {
  console.error('Missing required environment variables: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_EMAIL, ADMIN_PASSWORD');
  process.exit(1);
}

const supabase = createClient(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function main() {
  let userId;

  const existing = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (existing.error) throw existing.error;

  const existingUser = existing.data.users.find((user) => user.email?.toLowerCase() === email.toLowerCase());

  if (existingUser) {
    userId = existingUser.id;

    const updateResult = await supabase.auth.admin.updateUserById(userId, {
      password,
      email_confirm: true,
      user_metadata: {
        ...(existingUser.user_metadata || {}),
        full_name: fullName,
        role: 'admin',
      },
    });

    if (updateResult.error) throw updateResult.error;
    console.log(`Updated existing user ${email}`);
  } else {
    const created = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        role: 'admin',
      },
    });

    if (created.error || !created.data.user) throw created.error || new Error('Failed to create admin user');
    userId = created.data.user.id;
    console.log(`Created admin user ${email}`);
  }

  const profileUpsert = await supabase.from('profiles').upsert({
    id: userId,
    email,
    full_name: fullName,
    role: 'admin',
    email_verified: true,
    phone_verified: true,
    email_confirmed_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  });

  if (profileUpsert.error) throw profileUpsert.error;

  console.log(`Admin profile ready for ${email}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
