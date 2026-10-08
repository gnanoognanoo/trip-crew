-- =============================================================================
-- TripCrew Supabase PostgreSQL Schema & Atomic Payment Finalization RPC
-- =============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. USERS TABLE
CREATE TABLE IF NOT EXISTS public.users (
  uid VARCHAR PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  photo_url TEXT,
  trip_count INTEGER DEFAULT 0,
  distance_km DOUBLE PRECISION DEFAULT 0,
  memory_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. TRIPS TABLE
CREATE TABLE IF NOT EXISTS public.trips (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  destination TEXT,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  budget DOUBLE PRECISION DEFAULT 0,
  cover_image_url TEXT,
  invite_code TEXT UNIQUE,
  owner_uid TEXT NOT NULL,
  member_count INTEGER DEFAULT 1,
  status TEXT DEFAULT 'planning',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TRIP MEMBERS TABLE
CREATE TABLE IF NOT EXISTS public.trip_members (
  id TEXT PRIMARY KEY, -- 'tripId_uid'
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  display_name TEXT,
  photo_url TEXT,
  role TEXT DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  is_online BOOLEAN DEFAULT TRUE,
  last_active_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_trip_member UNIQUE(trip_id, uid)
);

-- 4. ITINERARY TABLE
CREATE TABLE IF NOT EXISTS public.itinerary (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  location TEXT,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  category TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. EXPENSES TABLE
CREATE TABLE IF NOT EXISTS public.expenses (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  amount_paise BIGINT NOT NULL,
  paid_by_uid TEXT NOT NULL,
  participant_uids JSONB DEFAULT '[]'::jsonb,
  category TEXT,
  date TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. CHECKLIST TABLE
CREATE TABLE IF NOT EXISTS public.checklist (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  task TEXT NOT NULL,
  is_completed BOOLEAN DEFAULT FALSE,
  assigned_to_uid TEXT,
  category TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. MEMORIES TABLE
CREATE TABLE IF NOT EXISTS public.memories (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  media_url TEXT NOT NULL,
  media_type TEXT DEFAULT 'image',
  caption TEXT,
  uploader_id TEXT,
  uploader_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. PULSES TABLE
CREATE TABLE IF NOT EXISTS public.pulses (
  id TEXT PRIMARY KEY, -- 'tripId_uid'
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  user_name TEXT,
  status_text TEXT,
  emoji TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_trip_pulse UNIQUE(trip_id, uid)
);

-- 9. LOCATIONS TABLE
CREATE TABLE IF NOT EXISTS public.locations (
  id TEXT PRIMARY KEY, -- 'tripId_uid'
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  user_name TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  battery_level DOUBLE PRECISION,
  is_sharing BOOLEAN DEFAULT TRUE,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_trip_location UNIQUE(trip_id, uid)
);

-- 10. TRIP PAY SUMMARY TABLE
CREATE TABLE IF NOT EXISTS public.trip_pay_summary (
  trip_id TEXT PRIMARY KEY REFERENCES public.trips(id) ON DELETE CASCADE,
  total_contributed_paise BIGINT DEFAULT 0,
  total_spent_paise BIGINT DEFAULT 0,
  available_balance_paise BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. PAYMENT ATTEMPTS TABLE
CREATE TABLE IF NOT EXISTS public.payment_attempts (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  type TEXT DEFAULT 'contribution',
  amount_paise BIGINT NOT NULL,
  platform_fee_paise BIGINT DEFAULT 0,
  total_charge_paise BIGINT NOT NULL,
  provider TEXT DEFAULT 'razorpay',
  client_request_id TEXT,
  payment_intent_id TEXT NOT NULL,
  status TEXT DEFAULT 'pending',
  provider_reference TEXT,
  verified_at TIMESTAMPTZ,
  ledger_transaction_id TEXT,
  failure_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookup by payment_intent_id
CREATE INDEX IF NOT EXISTS idx_payment_attempts_intent ON public.payment_attempts(payment_intent_id);

-- 12. TRANSACTIONS TABLE
CREATE TABLE IF NOT EXISTS public.transactions (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  type TEXT DEFAULT 'contribution',
  amount_paise BIGINT NOT NULL,
  initiated_by_uid TEXT NOT NULL,
  initiated_by_name TEXT,
  category TEXT DEFAULT 'Contribution',
  description TEXT,
  status TEXT DEFAULT 'sandboxSuccess',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  balance_before_paise BIGINT DEFAULT 0,
  balance_after_paise BIGINT DEFAULT 0,
  calculated_platform_fee_paise BIGINT DEFAULT 0,
  mode TEXT DEFAULT 'sandbox',
  client_request_id TEXT,
  provider_reference TEXT UNIQUE
);

-- 13. SETTLEMENTS TABLE
CREATE TABLE IF NOT EXISTS public.settlements (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  from_uid TEXT NOT NULL,
  from_name TEXT,
  to_uid TEXT NOT NULL,
  to_name TEXT,
  amount_paise BIGINT NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. TRIP INVITES TABLE
CREATE TABLE IF NOT EXISTS public.trip_invites (
  invite_code TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 15. MEDIA CLEANUP QUEUE TABLE
CREATE TABLE IF NOT EXISTS public.media_cleanup_queue (
  id TEXT PRIMARY KEY,
  storage_path TEXT NOT NULL,
  requested_by TEXT,
  trip_id TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 16. BETA FEEDBACK TABLE
CREATE TABLE IF NOT EXISTS public.beta_feedback (
  id TEXT PRIMARY KEY,
  uid TEXT,
  message TEXT NOT NULL,
  device_model TEXT,
  os_version TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- ATOMIC PAYMENT FINALIZATION PL/pgSQL FUNCTION (RPC)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.finalize_payment_attempt(
  p_trip_id TEXT,
  p_payment_intent_id TEXT,
  p_provider_reference TEXT,
  p_initiated_by_name TEXT,
  p_amount_paise BIGINT DEFAULT NULL,
  p_mode TEXT DEFAULT 'sandbox'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_attempt public.payment_attempts%ROWTYPE;
  v_summary public.trip_pay_summary%ROWTYPE;
  v_tx_id TEXT;
  v_now TIMESTAMPTZ := NOW();
  v_balance_before BIGINT := 0;
  v_balance_after BIGINT := 0;
  v_amount BIGINT;
  v_fee BIGINT;
  v_existing_tx public.transactions%ROWTYPE;
BEGIN
  -- 1. Idempotency Check: Has provider_reference already been processed?
  IF p_provider_reference IS NOT NULL AND p_provider_reference <> '' THEN
    SELECT * INTO v_existing_tx FROM public.transactions WHERE provider_reference = p_provider_reference LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'idempotent', true,
        'transaction_id', v_existing_tx.id,
        'amount_paise', v_existing_tx.amount_paise,
        'status', 'success'
      );
    END IF;
  END IF;

  -- 2. Locate Payment Attempt by ID or payment_intent_id
  SELECT * INTO v_attempt FROM public.payment_attempts
  WHERE id = p_payment_intent_id OR payment_intent_id = p_payment_intent_id
  LIMIT 1;

  IF NOT FOUND THEN
    -- Fallback attempt creation if missing
    v_amount := COALESCE(p_amount_paise, 200);
    v_fee := ROUND(v_amount * 0.01);
  ELSE
    v_amount := v_attempt.amount_paise;
    v_fee := v_attempt.platform_fee_paise;
  END IF;

  -- 3. Lock and fetch Trip Pot Summary for update
  SELECT * INTO v_summary FROM public.trip_pay_summary
  WHERE trip_id = p_trip_id FOR UPDATE;

  IF FOUND THEN
    v_balance_before := COALESCE(v_summary.available_balance_paise, 0);
  ELSE
    v_balance_before := 0;
  END IF;

  v_balance_after := v_balance_before + v_amount;

  -- 4. Generate Ledger Transaction ID
  v_tx_id := 'tx_' || EXTRACT(EPOCH FROM v_now)::BIGINT || '_' || ABS(HASHTEXT(COALESCE(v_attempt.uid, 'user_anon')));

  -- 5. Insert Ledger Transaction Record
  INSERT INTO public.transactions (
    id,
    trip_id,
    type,
    amount_paise,
    initiated_by_uid,
    initiated_by_name,
    category,
    description,
    status,
    created_at,
    balance_before_paise,
    balance_after_paise,
    calculated_platform_fee_paise,
    mode,
    client_request_id,
    provider_reference
  ) VALUES (
    v_tx_id,
    p_trip_id,
    'contribution',
    v_amount,
    COALESCE(v_attempt.uid, 'uid_user'),
    COALESCE(p_initiated_by_name, 'Member'),
    'Contribution',
    COALESCE(p_initiated_by_name, 'Member') || ' added money (UPI)',
    'sandboxSuccess',
    v_now,
    v_balance_before,
    v_balance_after,
    v_fee,
    p_mode,
    COALESCE(v_attempt.client_request_id, 'cr_' || p_payment_intent_id),
    p_provider_reference
  );

  -- 6. Update or Insert Trip Pot Summary
  INSERT INTO public.trip_pay_summary (
    trip_id,
    total_contributed_paise,
    total_spent_paise,
    available_balance_paise,
    updated_at
  ) VALUES (
    p_trip_id,
    COALESCE(v_summary.total_contributed_paise, 0) + v_amount,
    COALESCE(v_summary.total_spent_paise, 0),
    v_balance_after,
    v_now
  )
  ON CONFLICT (trip_id) DO UPDATE SET
    total_contributed_paise = public.trip_pay_summary.total_contributed_paise + v_amount,
    available_balance_paise = v_balance_after,
    updated_at = v_now;

  -- 7. Update Payment Attempt Status
  IF v_attempt.id IS NOT NULL THEN
    UPDATE public.payment_attempts SET
      status = 'success',
      provider_reference = p_provider_reference,
      verified_at = v_now,
      ledger_transaction_id = v_tx_id,
      updated_at = v_now
    WHERE id = v_attempt.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'transaction_id', v_tx_id,
    'amount_paise', v_amount,
    'balance_before_paise', v_balance_before,
    'balance_after_paise', v_balance_after,
    'status', 'success'
  );
END;
$$;
