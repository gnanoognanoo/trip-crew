-- ============================================================
-- TRIPCREW MIGRATION: Itinerary, Checklist & Trip Schema Expansion
-- ============================================================
-- Contains ONLY columns confirmed missing from remote PostgreSQL schema.
-- Uses non-destructive ALTER TABLE ADD COLUMN IF NOT EXISTS with safe defaults.
-- Existing data is 100% preserved.

-- 1. Itinerary: day_number and time
ALTER TABLE itinerary_items ADD COLUMN IF NOT EXISTS day_number INT DEFAULT 1;
ALTER TABLE itinerary_items ADD COLUMN IF NOT EXISTS time TEXT DEFAULT '10:00 AM';

-- 2. Checklist: category
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'Clothes';

-- 3. Trips: status, budget, starting_place
ALTER TABLE trips ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'upcoming';
ALTER TABLE trips ADD COLUMN IF NOT EXISTS budget NUMERIC(12, 2) DEFAULT 0;
ALTER TABLE trips ADD COLUMN IF NOT EXISTS starting_place TEXT;
