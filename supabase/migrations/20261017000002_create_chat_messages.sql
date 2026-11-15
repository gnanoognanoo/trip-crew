-- ============================================================
-- 1. Chat Messages Table
-- ============================================================
CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  user_name TEXT NOT NULL,
  message_type TEXT NOT NULL DEFAULT 'text', -- 'text', 'voice', 'location'
  content TEXT,
  audio_duration_seconds INT DEFAULT 0,
  latitude NUMERIC(10, 7),
  longitude NUMERIC(10, 7),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_trip ON chat_messages(trip_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_created ON chat_messages(trip_id, created_at);

ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read/write for chat_messages" ON chat_messages;
CREATE POLICY "Allow public read/write for chat_messages" ON chat_messages FOR ALL USING (true) WITH CHECK (true);

-- ============================================================
-- 2. Storage Bucket for Voice Messages
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('trip-audio', 'trip-audio', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Allow public uploads to trip-audio" ON storage.objects;
CREATE POLICY "Allow public uploads to trip-audio" ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'trip-audio');

DROP POLICY IF EXISTS "Allow public read for trip-audio" ON storage.objects;
CREATE POLICY "Allow public read for trip-audio" ON storage.objects FOR SELECT
USING (bucket_id = 'trip-audio');

