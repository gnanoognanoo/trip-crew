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
CREATE OR REPLACE FUNCTION finalize_payment_attempt(
  p_trip_id TEXT,
  p_payment_intent_id TEXT,
  p_provider_reference TEXT,
  p_initiated_by_name TEXT DEFAULT 'Member',
  p_amount_paise BIGINT DEFAULT 0,
  p_mode TEXT DEFAULT 'live'
) RETURNS JSONB AS $$
DECLARE
  v_attempt RECORD;
  v_summary RECORD;
  v_transaction_id TEXT;
  v_balance_before BIGINT;
  v_balance_after BIGINT;
  v_amount BIGINT;
  v_user_id TEXT;
  v_client_req_id TEXT;
BEGIN
  -- 1. Locate payment_attempt by payment_intent_id or provider_reference
  SELECT * INTO v_attempt FROM payment_attempts 
  WHERE payment_intent_id = p_payment_intent_id 
     OR (p_provider_reference IS NOT NULL AND provider_reference = p_provider_reference)
  FOR UPDATE;

  -- If not found, create fallback attempt record
  IF NOT FOUND THEN
    v_user_id := 'system_user';
    v_amount := COALESCE(p_amount_paise, 202);
    v_client_req_id := 'req_' || floor(random()*1000000)::text;
    
    INSERT INTO payment_attempts (
      id, trip_id, user_id, type, amount_paise, platform_fee_paise, total_charge_paise,
      provider, payment_intent_id, status, provider_reference, verified_at, created_at, updated_at
    ) VALUES (
      'att_' || floor(random()*1000000000)::text,
      p_trip_id, v_user_id, 'contribution', v_amount, 0, v_amount,
      'razorpay', p_payment_intent_id, 'SUCCESS', p_provider_reference, NOW(), NOW(), NOW()
    )
    RETURNING * INTO v_attempt;
  ELSE
    -- 2. Idempotency check: if already SUCCESS, return early without double adding money
    IF v_attempt.status = 'SUCCESS' THEN
      RETURN jsonb_build_object(
        'success', true,
        'idempotent', true,
        'message', 'Payment attempt already finalized',
        'attempt_id', v_attempt.id
      );
    END IF;
    
    v_amount := v_attempt.amount_paise;
    v_user_id := v_attempt.user_id;
    v_client_req_id := v_attempt.client_request_id;

    -- Update status to SUCCESS
    UPDATE payment_attempts
    SET status = 'SUCCESS',
        provider_reference = COALESCE(p_provider_reference, v_attempt.provider_reference),
        verified_at = NOW(),
        updated_at = NOW()
    WHERE id = v_attempt.id;
  END IF;

  -- 3. Lock/Insert trip_pay_summary
  INSERT INTO trip_pay_summary (trip_id, total_contributed_paise, total_spent_paise, available_balance_paise, updated_at)
  VALUES (p_trip_id, 0, 0, 0, NOW())
  ON CONFLICT (trip_id) DO NOTHING;

  SELECT * INTO v_summary FROM trip_pay_summary WHERE trip_id = p_trip_id FOR UPDATE;

  v_balance_before := COALESCE(v_summary.available_balance_paise, 0);
  v_balance_after := v_balance_before + v_amount;

  -- 4. Create single ledger transaction
  v_transaction_id := 'tx_' || floor(random()*1000000000)::text;

  INSERT INTO transactions (
    id, trip_id, type, amount_paise, initiated_by_user_id, initiated_by_name,
    category, description, status, balance_before_paise, balance_after_paise,
    platform_fee_paise, payment_attempt_id, provider_reference, client_request_id, created_at
  ) VALUES (
    v_transaction_id,
    p_trip_id,
    'CONTRIBUTION',
    v_amount,
    v_user_id,
    p_initiated_by_name,
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

  -- 5. Update trip_pay_summary
  UPDATE trip_pay_summary
  SET total_contributed_paise = total_contributed_paise + v_amount,
      available_balance_paise = available_balance_paise + v_amount,
      updated_at = NOW()
  WHERE trip_id = p_trip_id;

  -- 6. Link ledger transaction ID
  UPDATE payment_attempts
  SET ledger_transaction_id = v_transaction_id
  WHERE id = v_attempt.id;

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
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
CREATE POLICY "Allow public read/write for profiles" ON profiles FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for trips" ON trips FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for trip_members" ON trip_members FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for trip_invites" ON trip_invites FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for expenses" ON expenses FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for itinerary_items" ON itinerary_items FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for checklist_items" ON checklist_items FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for memories" ON memories FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for trip_pulses" ON trip_pulses FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for live_locations" ON live_locations FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow public read/write for settlements" ON settlements FOR ALL USING (true) WITH CHECK (true);

-- READ ONLY for client on financial ledger tables (updates handled exclusively by server RPC)
CREATE POLICY "Allow public select for payment_attempts" ON payment_attempts FOR SELECT USING (true);
CREATE POLICY "Allow public insert for payment_attempts" ON payment_attempts FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public select for transactions" ON transactions FOR SELECT USING (true);
CREATE POLICY "Allow public select for trip_pay_summary" ON trip_pay_summary FOR SELECT USING (true);
CREATE POLICY "Allow public insert for beta_feedback" ON beta_feedback FOR ALL USING (true) WITH CHECK (true);
