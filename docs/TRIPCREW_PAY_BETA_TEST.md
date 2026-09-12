# TripCrew Pay — Real Device Beta Test Checklist

This checklist defines the manual validation procedure for **TripCrew Pay (Sandbox Mode)** across physical Android devices using real Firebase Authentication accounts on the **Firebase Spark** free tier.

---

## Pre-Test Setup & Configuration

- **Environment**: Firebase Spark Free Tier (Authentication, Cloud Firestore, Cloud Storage, Cloudinary Free Tier).
- **Payment Mode**: **SANDBOX ONLY** (No real money is transferred, no UPI/RuPay gateways integrated).
- **Test Trip Details**:
  - **Trip Name**: Goa Road Trip 2026
  - **Trip Budget**: ₹20,000
  - **Target Contribution / Member**: ₹5,000
- **Test Accounts**:
  - **Account A** (Trip Owner / Member): `alpha@tripcrew.test` (Device 1)
  - **Account B** (Member): `beta@tripcrew.test` (Device 2)
  - **Account C** (Member): `gamma@tripcrew.test` (Device 3 or parallel session)
  - **Account D** (Member): `delta@tripcrew.test` (Device 4 or parallel session)
  - **Account E** (Non-Member): `epsilon@tripcrew.test` (Unauthorized test account)

---

## Test Scenarios & Verification Matrix

### 1. Account A Contribution
- [ ] **Action**: Account A opens Trip Workspace → **TripCrew Pay** → taps **"Add Your Share"**.
- [ ] **Input**: ₹5,000.
- [ ] **Verification**:
  - [ ] Screen clearly shows **"SANDBOX"** disclosure banner.
  - [ ] 1% platform fee preview shows **₹50** (integer calculation: `500000 * 100 / 10000 = 5000 paise`).
  - [ ] Disclaimer indicates fee is metadata and **not** deducted from or added to the Trip Pot.
  - [ ] Account A confirms sandbox contribution.
  - [ ] Firestore transaction created in `trips/{tripId}/transactions`:
    - `type`: `contribution`
    - `amountPaise`: `500000` (₹5,000)
    - `initiatedByUid`: Account A UID
    - `initiatedByName`: Account A Display Name
    - `mode`: `sandbox`
    - `clientRequestId`: Non-empty UUID
    - `createdAt`: Server timestamp
  - [ ] Trip Pot Available Balance updates to **₹5,000**.

---

### 2. Account B Contribution
- [ ] **Action**: Account B opens Trip Workspace → **TripCrew Pay** → taps **"Add Your Share"**.
- [ ] **Input**: ₹5,000.
- [ ] **Verification**:
  - [ ] Account B submits contribution.
  - [ ] Available balance updates to **₹10,000**.
  - [ ] Total contributed updates to **₹10,000**.

---

### 3. Account C Contribution
- [ ] **Action**: Account C opens **TripCrew Pay** → taps **"Add Your Share"**.
- [ ] **Input**: ₹5,000.
- [ ] **Verification**:
  - [ ] Account C submits contribution.
  - [ ] Available balance updates to **₹15,000**.
  - [ ] Total contributed updates to **₹15,000**.

---

### 4. Account D Contribution
- [ ] **Action**: Account D opens **TripCrew Pay** → taps **"Add Your Share"**.
- [ ] **Input**: ₹5,000.
- [ ] **Verification**:
  - [ ] Account D submits contribution.
  - [ ] Total Contributed reaches **₹20,000** (`2000000 paise`).
  - [ ] Available Balance reaches **₹20,000** (`2000000 paise`).
  - [ ] Pot Progress bar shows **100%** funded.

---

### 5. Realtime Transaction Visibility (Cross-Device)
- [ ] **Verification**:
  - [ ] Keep Account A (Device 1) and Account B (Device 2) on the TripCrew Pay screen simultaneously.
  - [ ] When Account C or D contributes, Devices 1 & 2 update their balance and ledger **automatically in realtime** without manual pull-to-refresh.
  - [ ] All 4 members observe identical available balance (₹20,000) and contribution totals.

---

### 6. Payment 1 by Account A (Dinner ₹1,200)
- [ ] **Action**: Account A taps **"Pay from Trip Pot"**.
- [ ] **Input**:
  - Title: `Dinner`
  - Amount: `₹1,200`
  - Category: `Food`
  - Notes: `Team Dinner at Beach Shack`
- [ ] **Verification**:
  - [ ] Trip Pot available balance decreases from **₹20,000** → **₹18,800**.
  - [ ] New transaction record created:
    - `type`: `payment`
    - `amountPaise`: `120000`
    - `initiatedByUid`: Account A UID
    - `initiatedByName`: Account A Display Name
    - `balanceBeforePaise`: `2000000`
    - `balanceAfterPaise`: `1880000`
    - `relatedExpenseId`: Valid expense ID
  - [ ] UI shows transaction: `Dinner • -₹1,200` initiated by Account A.

---

### 7. Payment 2 by Account B (Fuel ₹2,000)
- [ ] **Action**: Account B taps **"Pay from Trip Pot"**.
- [ ] **Input**:
  - Title: `Fuel`
  - Amount: `₹2,000`
  - Category: `Transport`
  - Notes: `Highway Petrol Bunk`
- [ ] **Verification**:
  - [ ] Trip Pot available balance decreases from **₹18,800** → **₹16,800**.
  - [ ] Ledger entry displays exact required wording:
    `"Account B initiated a ₹2,000 payment from the Trip Pot"`
  - [ ] Subtitle explicitly confirms payment was drawn from shared pot, **NOT** personally paid out-of-pocket by Account B.
  - [ ] All members (A, B, C, D) instantly see the updated balance of **₹16,800**.

---

### 8. Automatic Expense Creation & Linkage
- [ ] **Action**: Navigate to Trip Workspace → **Expenses** tab.
- [ ] **Verification**:
  - [ ] Expense 1 exists: `Dinner` — ₹1,200 (Category: Food, Paid by: Account A).
  - [ ] Expense 2 exists: `Fuel` — ₹2,000 (Category: Transport, Paid by: Account B).
  - [ ] Both expenses contain metadata: `paymentSource = 'TripCrew Pay'`.
  - [ ] No duplicate expenses are generated.
  - [ ] Expense split includes all active trip members equally by default.

---

### 9. Transaction History Ordering & Details
- [ ] **Action**: Inspect transaction history list on TripCrew Pay screen.
- [ ] **Verification**:
  - [ ] Ordering is strictly descending by actual server timestamp:
    1. `Account B • Fuel • -₹2,000`
    2. `Account A • Dinner • -₹1,200`
    3. `Account D • Contribution • +₹5,000`
    4. `Account C • Contribution • +₹5,000`
    5. `Account B • Contribution • +₹5,000`
    6. `Account A • Contribution • +₹5,000`
  - [ ] Tapping any transaction opens the bottom sheet showing:
    - Transaction Type & Status (`SANDBOX SUCCESS`)
    - Client Request ID & Firestore ID
    - Balance Before & Balance After
    - Linked Expense ID (for payments)

---

### 10. Append-Only Ledger Security
- [ ] **Action**: Attempt unauthorized modifications directly via Firestore client or debugging tools:
  - [ ] Attempt to update `amountPaise` of an existing transaction: **FAIL** (`PERMISSION_DENIED`).
  - [ ] Attempt to delete a transaction document: **FAIL** (`PERMISSION_DENIED`).
  - [ ] Attempt to change `initiatedByUid` on existing record: **FAIL** (`PERMISSION_DENIED`).
- [ ] **Verification**: Ledger documents in `trips/{tripId}/transactions/{txId}` are immutable.

---

### 11. Impersonation Attack Prevention
- [ ] **Action**: Authenticate as Account B, craft a payment transaction payload with `initiatedByUid = Account A UID`.
- [ ] **Verification**:
  - [ ] Write is rejected by Firestore security rules (`request.resource.data.initiatedByUid == request.auth.uid`).
  - [ ] Return status: `PERMISSION_DENIED`.

---

### 12. Non-Member Access Check
- [ ] **Action**: Authenticate as Account E (user who has NOT joined the trip).
- [ ] **Verification**:
  - [ ] Read `trips/{tripId}/tripPay/summary`: **FAIL** (`PERMISSION_DENIED`).
  - [ ] Read `trips/{tripId}/transactions`: **FAIL** (`PERMISSION_DENIED`).
  - [ ] Attempt contribution or payment write: **FAIL** (`PERMISSION_DENIED`).

---

### 13. Removed Member Access
- [ ] **Action**: Trip Owner removes Account D from the crew.
- [ ] **Verification**:
  - [ ] Account D is immediately blocked from creating new contributions or payments.
  - [ ] Historical contribution from Account D (+₹5,000) remains visible in the shared ledger.
  - [ ] Account D's name remains associated with past transactions.

---

### 14. Insufficient Balance Protection
- [ ] **Action**: With current balance at **₹16,800**, attempt a payment of **₹20,000**.
- [ ] **Verification**:
  - [ ] UI immediately blocks action with error: `"Insufficient Trip Pot balance."`.
  - [ ] Provider transaction execution blocks with `StateError('Insufficient Trip Pot balance.')`.
  - [ ] No transaction document is written to Firestore.
  - [ ] No expense document is created.
  - [ ] Balance remains unchanged at **₹16,800**.

---

### 15. Zero / Negative / Malformed Amount Validation
- [ ] **Action**: In "Add Your Share" or "Pay from Trip Pot":
  - [ ] Enter `₹0`: **BLOCKED** (Submit button disabled or validation message).
  - [ ] Enter `-₹500`: **BLOCKED**.
  - [ ] Enter non-numeric / decimal overflow: **BLOCKED**.

---

### 16. Duplicate Tap Idempotency Test
- [ ] **Action**: On "Pay from Trip Pot" confirmation, rapidly tap the confirm button 5 times.
- [ ] **Verification**:
  - [ ] Button disables on initial tap.
  - [ ] `clientRequestId` idempotency guard prevents duplicate transaction creation.
  - [ ] Exactly **ONE** transaction is created in the ledger.
  - [ ] Exactly **ONE** expense is created in the expenses list.

---

### 17. Network Loss / Offline Behavior
- [ ] **Action**: Switch device to Airplane Mode.
- [ ] **Attempt**: Tap "Add Your Share" or "Pay from Trip Pot".
- [ ] **Verification**:
  - [ ] Action is blocked with message: `"TripCrew Pay requires an internet connection."`.
  - [ ] No optimistic false-success state is shown.
  - [ ] Transactions are not queued silently for delayed corruption.

---

### 18. Concurrent Payment Collision Test
- [ ] **Scenario**: Available balance is **₹16,800**.
  - [ ] Account A attempts payment of **₹10,000**.
  - [ ] Account B attempts payment of **₹10,000** simultaneously.
- [ ] **Verification**:
  - [ ] Firestore `runTransaction` serializes the reads and writes.
  - [ ] First transaction succeeds (balance drops to ₹6,800).
  - [ ] Second transaction fails with `"Insufficient Trip Pot balance."`.
  - [ ] Available balance **never becomes negative**.

---

### 19. Sandbox Refund Ledger Test
- [ ] **Action**: Account A opens transaction details for `Dinner (-₹1,200)` and triggers **Sandbox Refund**.
- [ ] **Verification**:
  - [ ] Original payment record is **NOT** modified or deleted.
  - [ ] New refund transaction is appended:
    - `type`: `refund`
    - `amountPaise`: `120000` (+₹1,200)
    - `relatedTransactionId`: ID of original Dinner transaction
  - [ ] Available balance increases from **₹16,800** → **₹18,000**.
  - [ ] Net spent reflects reduction.

---

### 20. App Restart & Session Persistence
- [ ] **Action**: Force kill the TripCrew app and relaunch.
- [ ] **Verification**:
  - [ ] User remains authenticated.
  - [ ] Navigating to Trip Workspace → TripCrew Pay loads current state immediately.
  - [ ] All 7 transactions (4 contributions + 2 payments + 1 refund) render correctly.
  - [ ] Balance displays exactly **₹18,000**.

---

### 21. Source of Truth Reconciliation Audit
- [ ] **Action**: Run `TripPayReconciler.reconcile(...)` against ledger and summary.
- [ ] **Verification**:
  - [ ] Sum of contributions (`₹20,000`) minus net payments (`₹2,000` = `₹3,200` payments - `₹1,200` refund) == `₹18,000`.
  - [ ] Summary `availableBalancePaise` == Ledger calculated balance (`1800000 paise`).
  - [ ] Result is flagged as **MATCH** with 0 discrepancies.

---

### 22. Trip-End Settlement Preview
- [ ] **Action**: Open TripCrew Pay → Settlement / Trip Summary.
- [ ] **Verification**:
  - [ ] Displays total contributed: `₹20,000`.
  - [ ] Displays total spent: `₹2,000`.
  - [ ] Displays remaining balance: `₹18,000`.
  - [ ] Shows dynamic proportional return breakdown (₹4,500/member for 4 equal contributors).
  - [ ] Clearly labelled as **"Sandbox Settlement Preview — No real funds moved"**.

---

### 23. Real Money & Sensitive Credential Boundary
- [ ] **Verification**:
  - [ ] Zero inputs for UPI PIN, CVV, Card Number, Expiry, or Bank Passwords.
  - [ ] No RuPay SDK or payment gateway dependencies.
  - [ ] Firebase remains strictly on Spark free tier.
