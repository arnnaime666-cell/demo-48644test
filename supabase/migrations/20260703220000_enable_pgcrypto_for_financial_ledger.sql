-- Financial ledger sealing uses digest(..., 'sha256') from pgcrypto.
-- Some production databases can have the table/trigger migration recorded
-- without the extension being present, which causes checkout payment detail
-- updates to fail when the ledger trigger runs.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
