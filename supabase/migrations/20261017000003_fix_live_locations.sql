-- Ensure live_locations has all columns needed for live crew tracking
ALTER TABLE live_locations ADD COLUMN IF NOT EXISTS accuracy DOUBLE PRECISION;
ALTER TABLE live_locations ADD COLUMN IF NOT EXISTS is_sharing BOOLEAN DEFAULT true;
ALTER TABLE live_locations ADD COLUMN IF NOT EXISTS sharing_mode TEXT DEFAULT 'off';
ALTER TABLE live_locations ADD COLUMN IF NOT EXISTS sharing_until TIMESTAMPTZ;
ALTER TABLE live_locations ADD COLUMN IF NOT EXISTS photo_url TEXT;

-- Drop and recreate permissive RLS policy for live_locations
ALTER TABLE live_locations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read/write for live_locations" ON live_locations;
CREATE POLICY "Allow public read/write for live_locations" ON live_locations FOR ALL USING (true) WITH CHECK (true);

-- Enable publication in supabase_realtime for live tracking
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE live_locations;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE trip_pulses;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE trip_members;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;

