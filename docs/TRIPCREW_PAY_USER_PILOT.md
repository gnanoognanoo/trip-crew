# TripCrew Pay — Real 4-Person User Pilot Guide & Checklist

This document details the operational plan, field testing scenario, stress test instructions, and post-trip user feedback questions for the **TripCrew Pay Sandbox Beta Pilot**.

---

## 1. Pilot Goals & Ground Rules

- **Primary Goal**: Test whether the shared Trip Pot user experience is genuinely intuitive, reduces friction in group outings, and creates transparency without arguments.
- **Payment Mode**: **SANDBOX ONLY**. No real money is transferred. All transactions simulate real-world group expenditure.
- **Infrastructure**: Firebase Spark free tier (Firestore, Authentication, Cloud Storage, Cloudinary Free Tier).
- **Target Audience**: 4 real people on an outing or trip using Android physical devices.

---

## 2. 4-Person Pilot Test Scenario

### Outing Details
- **Trip Name**: `TripCrew Pilot`
- **Budget Target**: `₹20,000`
- **Crew Members**:
  - **Member A** (Trip Owner)
  - **Member B**
  - **Member C**
  - **Member D**

### Phase 1: Shared Pot Contributions
1. Member A creates trip `TripCrew Pilot` with budget `₹20,000`.
2. Members B, C, and D join via the Trip Invite code.
3. All 4 members open **TripCrew Pay** in their Trip Workspace.
4. Each member observes the first-time explanation:
   > *"Everyone in your crew adds their share to one shared Trip Pot.*
   > *Any joined crew member can use the pot during the trip.*
   > *Every payment records who initiated it so the entire crew can see where the money went."*
5. Each member contributes **₹5,000**:
   - Member A adds ₹5,000
   - Member B adds ₹5,000
   - Member C adds ₹5,000
   - Member D adds ₹5,000
6. **Expected Shared State Across All 4 Devices**:
   - **Trip Target**: `₹20,000`
   - **Collected / Total Added**: `₹20,000`
   - **Available Balance**: `₹20,000`
   - **Progress**: `100%`
   - **Crew Status**:
     - `Member A: ₹5,000 ✅`
     - `Member B: ₹5,000 ✅`
     - `Member C: ₹5,000 ✅`
     - `Member D: ₹5,000 ✅`

---

### Phase 2: Outing Payments from Shared Pot
During the outing, members take turns initiating payments for group expenses:

1. **Member A initiates**:
   - Item: `Breakfast`
   - Amount: `₹800`
   - Category: `Food`
   - *Expected Pot Balance*: `₹20,000` → `₹19,200`
   - *Verification*: Success screen shows `Payment Recorded ✓ • ₹800 • Breakfast • Initiated by Member A • Remaining: ₹19,200`. Auto-expense created with `paymentSource = 'TripCrew Pay'`.

2. **Member B initiates**:
   - Item: `Fuel`
   - Amount: `₹2,000`
   - Category: `Fuel` / `Transport`
   - *Expected Pot Balance*: `₹19,200` → `₹17,200`
   - *Verification*: Ledger displays `"Account B initiated a ₹2,000 payment from the Trip Pot"`. Auto-expense created.

3. **Member C initiates**:
   - Item: `Tickets`
   - Amount: `₹1,600`
   - Category: `Tickets`
   - *Expected Pot Balance*: `₹17,200` → `₹15,600`
   - *Verification*: Auto-expense created.

4. **Member D initiates**:
   - Item: `Coffee`
   - Amount: `₹600`
   - Category: `Food`
   - *Expected Pot Balance*: `₹15,600` → `₹15,000`
   - *Verification*: Auto-expense created.

### Phase 3: Outing Summary Verification
- **Total Contributed**: `₹20,000`
- **Total Spent**: `₹5,000` (`₹800 + ₹2,000 + ₹1,600 + ₹600`)
- **Remaining Trip Pot Balance**: `₹15,000`
- **All 4 phones must show identical**:
  - Available balance (`₹15,000`)
  - Transaction history order (most recent on top)
  - Payment initiators and human-readable timestamps (`Today • 8:42 PM`)
  - Auto-generated expense records in the Expenses tab.

---

## 3. Real-World Stress Test Checklist

During the outing, perform these edge-case resilience tests:

- [ ] **Lock / Reopen App**:
  Lock phone for 5 minutes during the outing, unlock, and return to TripCrew Pay. Ensure balance and history render immediately without crashing.
- [ ] **Switch Network (Wi-Fi ↔ Mobile Data)**:
  Switch between mobile data and hotel/café Wi-Fi. Confirm realtime stream reconnects cleanly.
- [ ] **Airplane Mode (Offline Check)**:
  Turn on Airplane Mode. Attempt "Pay from Trip Pot". Verify blocked with *"TripCrew Pay requires an internet connection."* Verify no corrupt transaction is created.
- [ ] **Simultaneous Viewing**:
  Have Member A and Member B open TripCrew Pay at the exact same moment. Confirm both load identical pot balance.
- [ ] **Near-Simultaneous Payments (Concurrency Collision)**:
  When available balance is ₹15,000, have Member A attempt a ₹10,000 payment and Member B attempt an ₹8,000 payment almost simultaneously.
  - *Expected*: First payment succeeds (balance drops to ₹5,000 or ₹7,000); second payment is blocked with *"Insufficient Trip Pot balance."*
  - *Crucial*: Pot balance must **NEVER** become negative.
- [ ] **No Duplicate Transactions / Expenses**:
  Verify rapid double-tapping on "Confirm Sandbox Payment" never generates duplicate records (idempotency key protection).
- [ ] **Live Crew & Trip Pulse Pilot Integration**:
  Optionally activate Live Crew location sharing and post Trip Pulses (e.g. `🍔 Hungry`, `☕ Need a Break`) to evaluate the complete TripCrew travel experience together.

---

## 4. Post-Trip Pilot Feedback Questionnaire

After completing the outing, ask each pilot tester the following 12 questions and record their responses:

1. **Was adding your share easy?**
2. **Did you understand how much money was available?**
3. **Did you understand that every joined member could use the pot?**
4. **Was it clear who initiated each payment?**
5. **Did TripCrew Pay reduce arguments/confusion about group expenses?**
6. **Would you prefer this over one friend paying everything and settling later?**
7. **Would you trust this feature with real money if backed by a regulated payment/banking partner?**
8. **Would you accept a 1% service fee on group pot contributions?**
9. **At what transaction or contribution amount would 1% feel too expensive?**
10. **What was confusing or awkward in the app?**
11. **What would stop you from using TripCrew Pay on your next real trip?**
12. **Would you use TripCrew again for another trip?**

---

## 5. In-App Beta Feedback

Testers can submit instant feedback during the trip:
- Open **Profile** → **Send Beta Feedback** (or tap the feedback icon in the TripCrew Pay AppBar).
- Select category: `TripCrew Pay`, `Live Crew`, `Bug`, `Confusing`, `Feature Request`, or `Other`.
- Describe the experience. Feedback is stored securely in Firestore `betaFeedback`.
