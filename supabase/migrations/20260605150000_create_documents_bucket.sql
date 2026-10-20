-- Create documents storage bucket for tutor document uploads
-- Run this via Supabase dashboard SQL editor or `supabase db push`

-- Create the bucket (if not exists)
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  true,
  false,
  10485760, -- 10MB limit (matching existing)
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage.objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Drop existing document policies to avoid conflicts when re-running
DROP POLICY IF EXISTS "Tutors can upload their own documents" ON storage.objects;
DROP POLICY IF EXISTS "Tutors can update their own documents" ON storage.objects;
DROP POLICY IF EXISTS "Tutors can delete their own documents" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can read documents" ON storage.objects;

-- Policy: Tutors can upload their own documents (path contains their user ID)
-- File path: tutor-docs/{userId}/{docKey}/{filename}
-- foldername()[2] = userId
CREATE POLICY "Tutors can upload their own documents"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Policy: Tutors can update their own documents
CREATE POLICY "Tutors can update their own documents"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Policy: Tutors can delete their own documents
CREATE POLICY "Tutors can delete their own documents"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Policy: Anyone can read documents (needed for admin review + tutor view)
CREATE POLICY "Anyone can read documents"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'documents');
