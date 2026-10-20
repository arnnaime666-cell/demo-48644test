-- Tutor vetting documents and family invoices contain sensitive personal data.
-- They must only be delivered through the authenticated, short-lived signed URL
-- endpoint in the application.

UPDATE storage.buckets
SET public = false
WHERE id = 'documents';

DROP POLICY IF EXISTS "Anyone can read documents" ON storage.objects;

COMMENT ON COLUMN public.sessions.invoice_url IS
  'Authenticated in-app URL for the private invoice PDF; never a public storage URL.';
