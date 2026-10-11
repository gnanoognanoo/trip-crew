-- ============================================================
-- TRIPCREW SUPABASE POSTGRESQL MIGRATION SCHEMA
-- ============================================================

-- 1. Profiles Table
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  email TEXT,
  display_name TEXT,
  photo_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Trips Table
CREATE TABLE IF NOT EXISTS trips (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  destination TEXT,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  created_by TEXT NOT NULL,
  member_count INT NOT NULL DEFAULT 1,
  invite_code TEXT UNIQUE,
  cover_photo_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Trip Members Table
CREATE TABLE IF NOT EXISTS trip_members (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uk_trip_member UNIQUE(trip_id, user_id)
);

-- 4. Trip Invites Table
CREATE TABLE IF NOT EXISTS trip_invites (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  invite_code TEXT UNIQUE NOT NULL,
  created_by TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN DEFAULT FALSE
);

-- 5. Expenses Table
CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  amount_paise BIGINT NOT NULL,
  paid_by_user_id TEXT NOT NULL,
  paid_by_name TEXT,
  category TEXT DEFAULT 'General',
  split_type TEXT DEFAULT 'EQUAL',
  date TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Itinerary Items Table
CREATE TABLE IF NOT EXISTS itinerary_items (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  location TEXT,
  date_time TIMESTAMPTZ,
  notes TEXT,
  is_completed BOOLEAN DEFAULT FALSE,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Checklist Items Table
CREATE TABLE IF NOT EXISTS checklist_items (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  is_completed BOOLEAN DEFAULT FALSE,
  assigned_to_user_id TEXT,
  assigned_to_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Memories Table
CREATE TABLE IF NOT EXISTS memories (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  media_url TEXT NOT NULL,
  caption TEXT,
  media_type TEXT DEFAULT 'image',
  cloudinary_public_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Trip Pulses Table
CREATE TABLE IF NOT EXISTS trip_pulses (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  user_name TEXT,
  pulse_type TEXT,
  type TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

-- 10. Live Locations Table
CREATE TABLE IF NOT EXISTS live_locations (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  user_name TEXT,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uk_live_location UNIQUE(trip_id, user_id)
);

-- 11. Settlements Table
CREATE TABLE IF NOT EXISTS settlements (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  from_user_id TEXT NOT NULL,
  from_user_name TEXT,
  to_user_id TEXT NOT NULL,
  to_user_name TEXT,
  amount_paise BIGINT NOT NULL,
  is_settled BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. Payment Attempts Table
CREATE TABLE IF NOT EXISTS payment_attempts (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'contribution',
  amount_paise BIGINT NOT NULL,
  platform_fee_paise BIGINT NOT NULL DEFAULT 0,
  total_charge_paise BIGINT NOT NULL,
  provider TEXT NOT NULL DEFAULT 'razorpay',
  client_request_id TEXT,
  payment_intent_id TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'CREATED',
  provider_reference TEXT,
  verified_at TIMESTAMPTZ,
  ledger_transaction_id TEXT,
  failure_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. Transactions / Ledger Table
CREATE TABLE IF NOT EXISTS transactions (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  amount_paise BIGINT NOT NULL,
  initiated_by_user_id TEXT NOT NULL,
  initiated_by_name TEXT,
  category TEXT,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'SUCCESS',
  balance_before_paise BIGINT NOT NULL DEFAULT 0,
  balance_after_paise BIGINT NOT NULL DEFAULT 0,
  platform_fee_paise BIGINT NOT NULL DEFAULT 0,
  payment_attempt_id TEXT REFERENCES payment_attempts(id),
  provider_reference TEXT,
  client_request_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uk_payment_attempt_ledger UNIQUE(payment_attempt_id)
);

-- 14. Trip Pay Summary Table
CREATE TABLE IF NOT EXISTS trip_pay_summary (
  trip_id TEXT PRIMARY KEY REFERENCES trips(id) ON DELETE CASCADE,
  total_contributed_paise BIGINT NOT NULL DEFAULT 0,
  total_spent_paise BIGINT NOT NULL DEFAULT 0,
  available_balance_paise BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 15. Beta Feedback Table
CREATE TABLE IF NOT EXISTS beta_feedback (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  feedback TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performant querying
CREATE INDEX IF NOT EXISTS idx_trip_members_user ON trip_members(user_id);
CREATE INDEX IF NOT EXISTS idx_trip_members_trip ON trip_members(trip_id);
CREATE INDEX IF NOT EXISTS idx_expenses_trip ON expenses(trip_id);
CREATE INDEX IF NOT EXISTS idx_itinerary_trip ON itinerary_items(trip_id);
CREATE INDEX IF NOT EXISTS idx_checklist_trip ON checklist_items(trip_id);
CREATE INDEX IF NOT EXISTS idx_memories_trip ON memories(trip_id);
CREATE INDEX IF NOT EXISTS idx_payment_attempts_trip ON payment_attempts(trip_id);
CREATE INDEX IF NOT EXISTS idx_payment_attempts_intent ON payment_attempts(payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_transactions_trip ON transactions(trip_id);

-- ============================================================
-- ATOMIC PAYMENT FINALIZATION RPC FUNCTION
-- ============================================================
DROP FUNCTION IF EXISTS finalize_payment_attempt(TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT);
DROP FUNCTION IF EXISTS finalize_payment_attempt(TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION finalize_payment_attempt(
  p_trip_id TEXT,
  p_payment_intent_id TEXT DEFAULT NULL,
  p_provider_reference TEXT DEFAULT NULL,
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

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE itinerary_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_pulses ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_pay_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE beta_feedback ENABLE ROW LEVEL SECURITY;

-- Permissive client access policies for authenticated/anon application usage
DROP POLICY IF EXISTS "Allow public read/write for profiles" ON profiles;
CREATE POLICY "Allow public read/write for profiles" ON profiles FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for trips" ON trips;
CREATE POLICY "Allow public read/write for trips" ON trips FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for trip_members" ON trip_members;
CREATE POLICY "Allow public read/write for trip_members" ON trip_members FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for trip_invites" ON trip_invites;
CREATE POLICY "Allow public read/write for trip_invites" ON trip_invites FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for expenses" ON expenses;
CREATE POLICY "Allow public read/write for expenses" ON expenses FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for itinerary_items" ON itinerary_items;
CREATE POLICY "Allow public read/write for itinerary_items" ON itinerary_items FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for checklist_items" ON checklist_items;
CREATE POLICY "Allow public read/write for checklist_items" ON checklist_items FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for memories" ON memories;
CREATE POLICY "Allow public read/write for memories" ON memories FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for trip_pulses" ON trip_pulses;
CREATE POLICY "Allow public read/write for trip_pulses" ON trip_pulses FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for live_locations" ON live_locations;
CREATE POLICY "Allow public read/write for live_locations" ON live_locations FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write for settlements" ON settlements;
CREATE POLICY "Allow public read/write for settlements" ON settlements FOR ALL USING (true) WITH CHECK (true);

-- READ ONLY for client on financial ledger tables (updates handled exclusively by server RPC)
DROP POLICY IF EXISTS "Allow public select for payment_attempts" ON payment_attempts;
CREATE POLICY "Allow public select for payment_attempts" ON payment_attempts FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow public insert for payment_attempts" ON payment_attempts;
CREATE POLICY "Allow public insert for payment_attempts" ON payment_attempts FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public select for transactions" ON transactions;
CREATE POLICY "Allow public select for transactions" ON transactions FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow public select for trip_pay_summary" ON trip_pay_summary;
CREATE POLICY "Allow public select for trip_pay_summary" ON trip_pay_summary FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow public insert for beta_feedback" ON beta_feedback;
CREATE POLICY "Allow public insert for beta_feedback" ON beta_feedback FOR ALL USING (true) WITH CHECK (true);
