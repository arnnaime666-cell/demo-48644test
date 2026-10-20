SELECT pg_catalog.set_config('role', 'postgres', true);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tutors can upload their own documents" ON storage.objects;
DROP POLICY IF EXISTS "Tutors can update their own documents" ON storage.objects;
DROP POLICY IF EXISTS "Tutors can delete their own documents" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can read documents" ON storage.objects;
CREATE POLICY "Tutors can upload their own documents"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
CREATE POLICY "Tutors can update their own documents"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
CREATE POLICY "Tutors can delete their own documents"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
CREATE POLICY "Anyone can read documents"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'documents');