# TripCrew — Complete Physical Mobile Device Test Protocol

This manual verification protocol must be executed on physical Android smartphones prior to opening the app to external beta testers or real-money pilot users.

---

## Device & Environment Prerequisites

- [ ] **Primary Device (Phone A — Trip Owner)**: Android 10+ with Google Play Services.
- [ ] **Secondary Device (Phone B — Member)**: Android 10+ with Google Play Services.
- [ ] **Tertiary Device (Phone C — Member)**: Android 10+ with Google Play Services (or emulator).
- [ ] **External Observer (Phone E — Non-member)**: Separate account for security boundary verification.
- [ ] **Internet**: Active Cellular (4G/5G) and Wi-Fi connections.
- [ ] **Location Services**: GPS enabled on Phones A & B.
- [ ] **Installed Build**: TripCrew Debug APK (`app-debug.apk`) or Release APK.

---

## Comprehensive Field Test Checklist

### 1. Installation & Initialization
- [ ] **Install APK**: APK installs cleanly without package corruption or missing abi warnings.
- [ ] **App Launch**: App opens directly to Welcome / Auth screen without white flash or startup crash.
- [ ] **Permissions Prompt**: Initial launch requests only baseline notifications; no aggressive premature GPS prompts.

### 2. Authentication & Account Management
- [ ] **Sign Up (Phone A)**: Register a fresh email/password account. User document created in `users/{uid}`.
- [ ] **Sign Up (Phone B, C, E)**: Register three additional test accounts.
- [ ] **Sign In**: Sign out and log back in on Phone A; credentials restore cleanly.
- [ ] **Logout & Session Restoration**: Force close app, reopen; session persists. Sign out explicitly; navigates to Welcome.
- [ ] **Invalid Auth Handling**: Test bad password and malformed email; user-friendly error banners display.

### 3. Trip Creation & Owner Role
- [ ] **Create Trip (Phone A)**: Create trip "Goa Roadtrip 2026" with ₹50,000 budget, start/end dates.
- [ ] **Owner Membership**: Phone A automatically assigned `owner` role, `memberCount = 1`.
- [ ] **Invite Code Generation**: High-entropy format `TC-XXXX-XXXX` generated and shareable.

### 4. Secure Join & Crew Management
- [ ] **Join Trip from Phone B**: Enter invite code `TC-XXXX-XXXX` with lowercase/mixed casing. Successfully joins.
- [ ] **Join Trip from Phone C**: Joins trip; crew count reflects 3 members on both Phone A and Phone B in realtime.
- [ ] **Invite Rejection**: Phone E enters an invalid code `TC-0000-0000` or expired invite; access blocked cleanly.
- [ ] **Realtime Crew List**: Phone A, B, and C all show the updated crew list with "Owner" badge on Phone A.
- [ ] **Member Removal**: Phone A (Owner) removes Phone C. Phone C immediately redirected to Trips screen.
- [ ] **Removed Member Access Block**: Phone C tries to access workspace or subcollections; permission denied.

### 5. TripCrew Pay (Shared Pot & Sandbox Ledger)
- [ ] **Pot Status Screen**: Available balance, Total Contributed, and Total Spent render ₹0.00.
- [ ] **Add Your Share (Phone A)**: Add ₹2,000 share. Fee calculated as ₹20 (1%), total debit ₹2,020.
- [ ] **Cross-Member Trip Pot Update**: Phone B immediately sees Available Balance update to ₹2,000.00.
- [ ] **Add Your Share (Phone B)**: Phone B adds ₹1,500 share. Available Balance becomes ₹3,500.00.
- [ ] **TripCrew Pay Spending (Phone B)**: Phone B pays ₹800 for "Lunch Dhaba" from the Shared Pot.
- [ ] **Balance Update**: Pot balance drops to ₹2,700.00 across all devices in realtime.
- [ ] **Transaction History & Who Paid**: Phone A and B both see: `"Lunch Dhaba - ₹800 - Initiated by [Phone B Name]"`.
- [ ] **Auto-Expense Creation**: Expense list contains ₹800 shared pot expense; participants auto-split.
- [ ] **Double Payment Tap**: Rapid double-tap on "Pay Now" with weak connection; only one transaction records (idempotent).
- [ ] **Overdraft Protection**: Phone B attempts to spend ₹5,000 when balance is ₹2,700; transaction blocked with clear message.

### 6. Dynamic Settlements
- [ ] **Settlement Preview**: Crew view shows simplified net balances (who owes whom) using minimal debt algorithm.
- [ ] **Dynamic Suggested Share**: Budget ₹50,000 divided among active members (not fixed to 4).

### 7. Smart Itinerary & Packing Checklist
- [ ] **Checklist Realtime Sync**: Phone A checks "First Aid Kit"; checkbox toggles instantly on Phone B.
- [ ] **Checklist Assignment**: Assign item to Phone B; Phone B sees visual indicator.
- [ ] **Itinerary Item Creation**: Phone B adds "Sunset at Anjuna" at 18:00; Phone A sees item in timeline.
- [ ] **Itinerary Visited State**: Mark activity as done; status synchronizes.

### 8. Shared Memories (Cloudinary Media)
- [ ] **Cloudinary Photo Upload**: Phone A selects a JPEG from camera/gallery, uploads to trip album.
- [ ] **Cross-Member Realtime Gallery**: Image appears in Phone B's memory feed within 3 seconds.
- [ ] **Cloudinary Avatar**: Phone B updates profile avatar from gallery; reflects across Crew view.
- [ ] **Large File Rejection**: Attempt to upload a file > 10MB; validated and rejected before network call.

### 9. Live Crew (Location Radar)
- [ ] **Contextual Permission**: Click "Share Location"; system prompt appears explaining battery/usage.
- [ ] **Location Permission Denied**: Deny permission; graceful fallback view without app crash.
- [ ] **Live Crew While App Open**: Phone A and Phone B share location; radar shows relative distance & bearing.
- [ ] **Proximity State (250m)**: Move within 250m; label displays "Together". Move beyond; displays distance in km.
- [ ] **Live Crew Background**: Minimize app on Phone A; location update continues via foreground service notification.
- [ ] **Live Crew Screen Locked**: Lock Phone A for 5 minutes; unlock Phone B; Phone A's location remains fresh.
- [ ] **Stop Sharing**: Click "Stop Sharing" on Phone A; coordinates immediately cleared from Firestore document.

### 10. Trip Pulse & Emergency SOS
- [ ] **Trip Pulse Post**: Phone B sets status "Hungry" with 30-minute expiry; displays in crew pulse bar.
- [ ] **Pulse Expiry**: Wait for pulse duration or click "Clear Status"; pulse vanishes across devices.
- [ ] **Emergency Confirmation**: Tap "Emergency / SOS"; dialog warns that this alerts crew only (no 112/police dispatch).
- [ ] **Emergency Alert**: Confirm SOS; high-priority banner displays on Phone A with current member coordinates.

### 11. Resilience & Network Failures
- [ ] **Offline Mode**: Turn on Airplane Mode; attempt to initiate TripCrew Pay payment; blocked with clear error.
- [ ] **Reconnect**: Re-enable network; pending state resolves cleanly without ghost transactions.
- [ ] **App Force-Close / Restart**: Force stop app while viewing workspace; reopen; restores to last known state.
