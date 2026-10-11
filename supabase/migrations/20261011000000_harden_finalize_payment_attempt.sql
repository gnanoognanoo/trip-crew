-- MIGRATION: Harden finalize_payment_attempt to tolerate trip_default fallback and ensure idempotency
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

  -- Verify trip_id (ignore empty, null, or fallback 'trip_default')
  IF p_trip_id IS NOT NULL AND p_trip_id <> '' AND p_trip_id <> 'trip_default' AND v_attempt.trip_id <> p_trip_id THEN
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
