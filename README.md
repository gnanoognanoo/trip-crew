# TripCrew

> **Plan • Travel • Share • Belong**

TripCrew is a collaborative group-travel platform where friends can plan a trip, manage their crew, contribute to a shared Trip Pot, track spending, coordinate during the trip, and preserve memories together.

---

## 🌟 Overview

Group travel is exciting, but organizing logistics, coordinating itineraries, splitting costs fairly, and keeping track of shared moments can be overwhelming. TripCrew is built to eliminate travel friction through an intuitive mobile workspace powered by real-time synchronization, strict database security invariants, and a transparent pooled financial system.

---

## 🚀 Feature Status Matrix

| Feature Module | Status | Description |
|---|---|---|
| **Firebase Authentication** | 🟢 **WORKING** | Email/password sign-up, sign-in, user profile state management |
| **Trip Creation** | 🟢 **WORKING** | Atomic creation of trip, owner membership, and unique invite codes |
| **Secure Invite Joining** | 🟢 **WORKING** | Safe single-document invite resolution, anti-enumeration, capacity guard |
| **Dynamic Crew (1–25)** | 🟢 **WORKING** | Dynamic crew capacity scaling up to 25 members with atomic Firestore counters |
| **Trip Workspace** | 🟢 **WORKING** | Central hub for all trip activities, quick actions, and status trackers |
| **Itinerary** | 🟢 **WORKING** | Daily activity scheduling, timeline view, and real-time syncing |
| **Checklist** | 🟢 **WORKING** | Shared packing checklist, item assignment, and completion tracking |
| **Expenses & Split** | 🟢 **WORKING** | Multi-payer expense logging, split calculation, debt minimization |
| **TripCrew Pay (Sandbox)** | 🟢 **WORKING** | Append-only financial ledger, idempotent contributions, 1% fee accounting |
| **Transaction History** | 🟢 **WORKING** | Complete audit trail of contributions, spending, and refunds |
| **Shared Trip Pot** | 🟢 **WORKING** | Real-time pooled balance display, contribution progress bar, goal tracking |
| **1% Platform Fee Calculation**| 🟢 **WORKING** | Decimal-safe integer paise conversion with explicit fee breakdown |
| **Live Crew Architecture** | 🟢 **WORKING** | Privacy-conscious location sharing, battery optimization, presence tracking |
| **Trip Pulse** | 🟢 **WORKING** | Quick vibe check-ins, mood reactions, and crew activity pulses |
| **Cloudinary Memories** | 🟢 **WORKING** | Unsigned preset uploads, HTTPS media storage, photo gallery feed |
| **Profile & Stats** | 🟢 **WORKING** | User stats, past trips history, settings, and sign out |
| **Real Money Movement** | 🟡 **SANDBOX** | Simulated test sandbox ledger; live production bank transfers not enabled |
| **Setu UPI Merchant v2 Collect**| 🔴 **BLOCKED / EXTERNAL**| Upstream sandbox endpoint dependency; fully implemented via local bridge |
| **Google Maps Integration** | 🟣 **COMING SOON** | Live interactive crew location map view with route navigation |
| **AI Travel Assistant** | 🔵 **PROTOTYPE** | Intelligent travel itinerary recommendations and budget insights |

> [!NOTE]
> TripCrew Pay operates safely in **Sandbox Mode** for pilot testing. Real-money UPI transfers require verified production merchant credentials.

---

## 🛠 Tech Stack

- **Frontend / Mobile**: Flutter 3.38+ (Dart 3.10+), Material 3, Riverpod 2.x State Management, GoRouter 14.x
- **Backend / Database**: Firebase Firestore (Security Rules v2 with strict `existsAfter` invariants), Firebase Authentication
- **Media Storage**: Cloudinary (Unsigned client uploads with zero API secret exposure)
- **Payment Gateway**: Setu UPI Merchant v2 (Node.js backend service / Sandbox bridge)
- **Testing**: Flutter Test Suite (245+ automated unit and integration tests)

---

## 📁 Project Structure

```text
tripcrew/
├── android/                   # Android native platform configuration & Gradle scripts
├── ios/                       # iOS native platform configuration
├── lib/
│   ├── app/                   # App root, router, and application theme
│   ├── core/                  # Global constants, errors, services, and shared widgets
│   │   └── services/          # Analytics, Cloudinary, Firebase, and Live Crew services
│   └── features/
│       ├── auth/              # Authentication models, screens, and Riverpod providers
│       ├── checklist/         # Packing checklist UI and providers
│       ├── crew/              # Crew members management and invite sharing
│       ├── expenses/          # Expense tracking and bill splitting
│       ├── home/              # Main dashboard and trip selector
│       ├── itinerary/         # Trip schedule and daily timeline
│       ├── maps/              # Live crew location sharing and maps architecture
│       ├── memories/          # Shared photo album backed by Cloudinary
│       ├── profile/           # User profile and account preferences
│       ├── pulse/             # Trip Pulse real-time check-in feature
│       ├── trip_pay/          # TripCrew Pay ledger, models, services, and UI
│       ├── trips/             # Trip creation, join flows, and workspace UI
│       └── workspace/         # Central trip operations workspace
├── server/                    # Node.js backend service for Setu UPI payment verification
├── test/                      # Comprehensive automated test suites (245+ tests)
├── docs/                      # Technical specs, pilot plans, and UAT setup guides
├── firestore.rules            # Hardened Firestore security rules
├── firestore.indexes.json     # Firestore composite index definitions
└── pubspec.yaml               # Flutter dependencies and assets declaration
```

---

## 🏁 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.38.9 or stable channel)
- Android Studio / VS Code with Flutter extensions
- Android Device or Emulator (API 26+)
- Node.js 20+ (optional, for backend payment server)

### 1. Clone the Repository

```bash
git clone https://github.com/gnanoognanoo/trip-crew.git
cd trip-crew
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Setup Environment Variables

Copy the example environment configuration:

```bash
cp .env.example .env
```

> [!CAUTION]
> **Never commit `.env` or any file containing private keys to GitHub.**

### 4. Run Quality Checks

```bash
flutter analyze
flutter test
```

### 5. Run the Application

```bash
flutter run
```

---

## 🔥 Firebase Setup

The repository is configured to connect to the Firebase project: `tripcrew-travel-2026`.

- **Client Configuration**: `lib/firebase_options.dart` and `android/app/google-services.json` are included in the repository. They contain public client identifiers and API keys, not private keys.
- **Security Rules**: Deployed with strict rules preventing unauthorized reads, role escalations, or counter drift. To deploy rules updates:
  ```bash
  firebase deploy --only firestore:rules
  ```

---

## ☁️ Cloudinary Setup

Cloudinary is used for uploading user avatars and trip memories:
- **Zero Client Secrets**: Uploads are performed directly from the mobile app via **unsigned upload presets**.
- **Presets configured**:
  - `tripcrew_avatar_upload` (User avatars, max 5 MB)
  - `tripcrew_memory_upload` (Trip memories, max 10 MB)
- Custom cloud name or presets can be supplied at build time:
  ```bash
  flutter run --dart-define=CLOUDINARY_CLOUD_NAME=your_cloud_name
  ```

---

## 💳 Payment Test Mode (TripCrew Pay)

TripCrew Pay operates out-of-the-box in **Sandbox Mode**:
- You can simulate adding funds to the shared Trip Pot using virtual test payment methods.
- Contributions atomically credit the append-only ledger and update the trip pot balance in paise.
- A 1% platform fee is automatically deducted and accounted for transparently.

To test with the Setu UPI backend service:
```bash
cd server
cp .env.example .env
npm install
node setu_backend_service.js
```

---

## 🤝 Team Collaboration

We follow a clean, collaborative Git workflow:

- **`main`**: Protected stable branch. All code must pass `flutter analyze` and `flutter test`.
- **Feature Branches**: Branch off `main` using `feature/<feature-name>` or `fix/<fix-name>`.
- Please read our [CONTRIBUTING.md](CONTRIBUTING.md) for full branch naming conventions, pull request guidelines, and code review standards.

---

## 🗺 Roadmap

- [x] Complete group trip planning and collaboration workspace
- [x] Shared Trip Pot ledger with decimal-safe integer paise calculations
- [x] Hardened invite-based join security and capacity enforcement (1–25)
- [x] Cloudinary shared memories feed
- [ ] Interactive Google Maps integration with route pins
- [ ] Real-time offline synchronization with SQLite caching
- [ ] Production UPI Payment Gateway onboarding
- [ ] AI-assisted travel expense categorization and itinerary builder

---

## 📄 License

Copyright © 2026 TripCrew. All rights reserved.
