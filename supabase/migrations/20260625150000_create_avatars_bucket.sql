-- Create avatars storage bucket for user profile photos
-- Run this via Supabase dashboard SQL editor or `supabase db push`

-- Bypass ownership check on storage.objects (same workaround as documents bucket migration)
SET ROLE postgres;

-- Create the bucket (if not exists)
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  false,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage.objects. On hosted Supabase, storage.objects is owned
-- by supabase_storage_admin and already has RLS enabled, so skip (rather than
-- fail) when we lack ownership.
DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping ALTER TABLE storage.objects: not owner (RLS is already enabled on hosted Supabase)';
END;
$$;

-- Drop existing avatar policies to avoid conflicts when re-running
DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can read avatars" ON storage.objects;

-- Policy: Authenticated users can upload their own avatar
-- File path: avatars/{userId}/avatar.{ext}
-- foldername()[2] = userId
CREATE POLICY "Users can upload their own avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Policy: Users can update their own avatar
CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Policy: Users can delete their own avatar
CREATE POLICY "Users can delete their own avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Policy: Anyone can read avatars (needed for public profile display)
CREATE POLICY "Anyone can read avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');
