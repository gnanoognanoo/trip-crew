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
  p_initiated_by_name TEXT DEFAULT 'Member',
  p_amount_paise BIGINT DEFAULT 0,
  p_mode TEXT DEFAULT 'live',
  p_payment_attempt_id TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_attempt RECORD;
  v_attempt_by_id RECORD;
  v_attempt_by_intent RECORD;
  v_summary RECORD;
  v_transaction_id TEXT;
  v_balance_before BIGINT;
  v_balance_after BIGINT;
  v_amount BIGINT;
  v_user_id TEXT;
  v_client_req_id TEXT;
BEGIN
  -- 1. Canonical lookup logic:
  -- Check if p_payment_attempt_id is provided
  IF p_payment_attempt_id IS NOT NULL AND p_payment_attempt_id <> '' THEN
    SELECT * INTO v_attempt_by_id FROM payment_attempts
    WHERE id = p_payment_attempt_id FOR UPDATE;
  END IF;

  -- Check by p_payment_intent_id
  IF p_payment_intent_id IS NOT NULL AND p_payment_intent_id <> '' THEN
    IF p_payment_intent_id LIKE 'att_%' AND v_attempt_by_id.id IS NULL THEN
      SELECT * INTO v_attempt_by_id FROM payment_attempts
      WHERE id = p_payment_intent_id FOR UPDATE;
    ELSE
      SELECT * INTO v_attempt_by_intent FROM payment_attempts
      WHERE payment_intent_id = p_payment_intent_id FOR UPDATE;
    END IF;
  END IF;

  -- If both are supplied and resolved, require them to point to the SAME row
  IF v_attempt_by_id.id IS NOT NULL AND v_attempt_by_intent.id IS NOT NULL THEN
    IF v_attempt_by_id.id <> v_attempt_by_intent.id THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'PAYMENT_ATTEMPT_MISMATCH',
        'message', 'Supplied payment_attempt_id and payment_intent_id resolve to different attempts'
      );
    END IF;
    v_attempt := v_attempt_by_id;
  ELSIF v_attempt_by_id.id IS NOT NULL THEN
    v_attempt := v_attempt_by_id;
  ELSIF v_attempt_by_intent.id IS NOT NULL THEN
    v_attempt := v_attempt_by_intent;
  ELSIF p_provider_reference IS NOT NULL AND p_provider_reference <> '' THEN
    SELECT * INTO v_attempt FROM payment_attempts
    WHERE provider_reference = p_provider_reference FOR UPDATE;
  END IF;

  -- 2. Strict Check: NO system_user fallback!
  IF v_attempt.id IS NULL OR v_attempt.id = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
      'message', 'No matching payment attempt was found for finalization'
    );
  END IF;

  -- Verify trip_id
  IF p_trip_id IS NOT NULL AND p_trip_id <> '' AND v_attempt.trip_id <> p_trip_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'TRIP_ID_MISMATCH',
      'message', 'Payment attempt trip_id does not match supplied trip_id'
    );
  END IF;

  -- Verify amount if supplied (>0)
  IF p_amount_paise IS NOT NULL AND p_amount_paise > 0 AND v_attempt.amount_paise <> p_amount_paise AND v_attempt.total_charge_paise <> p_amount_paise THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'AMOUNT_MISMATCH',
      'message', 'Payment attempt amount does not match supplied amount'
    );
  END IF;

  -- 3. Idempotency Check: If already SUCCESS, return early without double adding money
  IF v_attempt.status = 'SUCCESS' THEN
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'message', 'Payment attempt already finalized',
      'attempt_id', v_attempt.id,
      'transaction_id', v_attempt.ledger_transaction_id
    );
  END IF;

  v_amount := v_attempt.amount_paise;
  v_user_id := v_attempt.user_id;
  v_client_req_id := v_attempt.client_request_id;

  -- Update status to SUCCESS
  UPDATE payment_attempts
  SET status = 'SUCCESS',
      provider_reference = COALESCE(p_provider_reference, v_attempt.provider_reference),
      payment_intent_id = COALESCE(v_attempt.payment_intent_id, CASE WHEN p_payment_intent_id NOT LIKE 'att_%' THEN p_payment_intent_id ELSE NULL END),
      verified_at = NOW(),
      updated_at = NOW()
  WHERE id = v_attempt.id;

  -- 4. Lock/Insert trip_pay_summary
  INSERT INTO trip_pay_summary (trip_id, total_contributed_paise, total_spent_paise, available_balance_paise, updated_at)
  VALUES (v_attempt.trip_id, 0, 0, 0, NOW())
  ON CONFLICT (trip_id) DO NOTHING;

  SELECT * INTO v_summary FROM trip_pay_summary WHERE trip_id = v_attempt.trip_id FOR UPDATE;

  v_balance_before := COALESCE(v_summary.available_balance_paise, 0);
  v_balance_after := v_balance_before + v_amount;

  -- 5. Create single ledger transaction
  v_transaction_id := 'tx_' || floor(random()*1000000000)::text;

  INSERT INTO transactions (
    id, trip_id, type, amount_paise, initiated_by_user_id, initiated_by_name,
    category, description, status, balance_before_paise, balance_after_paise,
    platform_fee_paise, payment_attempt_id, provider_reference, client_request_id, created_at
  ) VALUES (
    v_transaction_id,
    v_attempt.trip_id,
    'CONTRIBUTION',
    v_amount,
    v_user_id,
    COALESCE(p_initiated_by_name, 'Member'),
    'Trip Pot Contribution',
    'Razorpay Contribution to Trip Pot',
    'SUCCESS',
    v_balance_before,
    v_balance_after,
    COALESCE(v_attempt.platform_fee_paise, 0),
    v_attempt.id,
    COALESCE(p_provider_reference, v_attempt.provider_reference),
    v_client_req_id,
    NOW()
  );

  -- 6. Update trip_pay_summary
  UPDATE trip_pay_summary
  SET total_contributed_paise = total_contributed_paise + v_amount,
      available_balance_paise = available_balance_paise + v_amount,
      updated_at = NOW()
  WHERE trip_id = v_attempt.trip_id;

  -- 7. Link ledger transaction ID
  UPDATE payment_attempts
  SET ledger_transaction_id = v_transaction_id
  WHERE id = v_attempt.id;

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'attempt_id', v_attempt.id,
    'transaction_id', v_transaction_id,
    'balance_before', v_balance_before,
    'balance_after', v_balance_after,
    'amount_added', v_amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
