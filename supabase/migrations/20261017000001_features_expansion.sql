-- ============================================================
-- TRIPCREW MIGRATION: 5 Feature Expansion
-- Memories storage, Itinerary Geo-coordinates, SOS pulse fields
-- ============================================================

-- 1. Memories Table: day_index & storage_path
ALTER TABLE memories ADD COLUMN IF NOT EXISTS day_index INT DEFAULT 1;
ALTER TABLE memories ADD COLUMN IF NOT EXISTS storage_path TEXT;

-- 2. Itinerary Items Table: latitude & longitude for Map & Routes
ALTER TABLE itinerary_items ADD COLUMN IF NOT EXISTS latitude NUMERIC(10, 7);
ALTER TABLE itinerary_items ADD COLUMN IF NOT EXISTS longitude NUMERIC(10, 7);

-- 3. Trip Pulses Table: geo-coordinates & message for Safety SOS
ALTER TABLE trip_pulses ADD COLUMN IF NOT EXISTS latitude NUMERIC(10, 7);
ALTER TABLE trip_pulses ADD COLUMN IF NOT EXISTS longitude NUMERIC(10, 7);
ALTER TABLE trip_pulses ADD COLUMN IF NOT EXISTS message TEXT;

-- 4. Supabase Storage: trip-memories bucket configuration
INSERT INTO storage.buckets (id, name, public)
VALUES ('trip-memories', 'trip-memories', true)
ON CONFLICT (id) DO NOTHING;

-- Permissive Storage RLS policies for trip memories bucket
DROP POLICY IF EXISTS "Allow public uploads to trip-memories" ON storage.objects;
CREATE POLICY "Allow public uploads to trip-memories"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'trip-memories');

DROP POLICY IF EXISTS "Allow public read for trip-memories" ON storage.objects;
CREATE POLICY "Allow public read for trip-memories"
ON storage.objects FOR SELECT
USING (bucket_id = 'trip-memories');

DROP POLICY IF EXISTS "Allow public delete for trip-memories" ON storage.objects;
CREATE POLICY "Allow public delete for trip-memories"
ON storage.objects FOR DELETE
USING (bucket_id = 'trip-memories');
