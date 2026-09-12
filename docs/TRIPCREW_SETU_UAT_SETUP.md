# TripCrew Pay — Setu UPI Sandbox / UAT Setup Guide

This guide details how to configure and test Setu UPI Sandbox / UAT mode with TripCrew Pay under Firebase Spark tier constraints.

---

## 1. Overview & Trust Architecture

TripCrew Pay separates the payment journey into distinct trust domains:

```
[Flutter Client] 
      │  (No secrets, user requests contribution)
      ▼
[Trusted TripCrew Backend]
      │  (Holds Setu Client Secret & Webhook Secret)
      ▼
[Setu UAT Gateway (https://uat.setu.co/api/v2)]
      │  (Issues UPI Intent / Link & test payment rails)
      ▼
[UPI Sandbox / Test Flow]
      │
      ▼
[Setu Webhook / Notification with x-setu-signature]
      │
      ▼
[Trusted TripCrew Backend]
      │  (Verifies HMAC-SHA256, matches exact amount + 1% fee, checks idempotency)
      ▼
[Firestore Immutable Ledger & Trip Pot Balance]
      │  (Realtime sync across all crew members)
      ▼
[All Crew Members See Updated Trip Pot]
```

---

## 2. Setu Bridge Sandbox Signup & Credentials

1. **Sign Up on The Bridge**:
   - Go to [https://bridge.setu.co/](https://bridge.setu.co/) and create a developer account.
2. **Create a Product Instance**:
   - Under **Products**, select **UPI Payment Links** / **UPI DeepLinks**.
   - Create a Sandbox / UAT product instance (e.g. `TripCrew Contribution Pot`).
3. **Obtain Credentials**:
   - Navigate to **Settings** / **API Keys** in the Bridge console.
   - Note down:
     - `Client ID`
     - `Client Secret`
     - `Product Instance ID`
     - `Webhook Secret` (generate under Webhooks settings)

> [!CAUTION]
> **Zero Secrets in Flutter**:
> Never put `SETU_CLIENT_SECRET` or `SETU_WEBHOOK_SECRET` inside Flutter client code or git repositories. They belong exclusively in backend environment variables.

---

## 3. Environment Variables Configuration

Copy `.env.example` to your trusted backend environment:

```bash
cp .env.example .env
```

Populate the variables with your sandbox values from Setu Bridge:

```env
# Provider Engine Selection ('sandbox' or 'setu')
PAYMENT_PROVIDER=setu

# Setu UAT Settings
SETU_ENVIRONMENT=uat
SETU_CLIENT_ID=your_actual_setu_client_id
SETU_CLIENT_SECRET=your_actual_setu_client_secret
SETU_PRODUCT_INSTANCE_ID=your_actual_product_instance_id
SETU_WEBHOOK_SECRET=your_actual_webhook_secret

# URL where trusted backend is hosted (e.g. Render, Cloudflare Workers, or local server)
TRIPCREW_BACKEND_URL=http://localhost:8080
```

---

## 4. Running the Trusted Backend Service

Because TripCrew remains on Firebase Spark tier (free tier), backend operations execute via a lightweight Node.js/Express server or serverless function (`server/setu_backend_service.js`):

```bash
cd server
npm install express
# Set environment variables and start server
PORT=8080 node setu_backend_service.js
```

Verify the health check:
```bash
curl http://localhost:8080/health
```

Expected output:
```json
{
  "status": "ok",
  "environment": "uat",
  "isConfigured": true,
  "message": "Setu UPI UAT Backend Ready"
}
```

---

## 5. Webhook & Callback Configuration in Setu Bridge

The trusted backend service is deployed with a free public HTTPS endpoint:

- **`PUBLIC_BACKEND_URL`**:
  `https://caused-possibilities-mount-costume.trycloudflare.com`
- **`SETU_CALLBACK_BASE_URL`**:
  `https://caused-possibilities-mount-costume.trycloudflare.com/api/v1/payments/setu`
- **`SETU_NOTIFICATION_URL`**:
  `https://caused-possibilities-mount-costume.trycloudflare.com/api/v1/payments/setu/notifications`

### Setup in Setu Bridge Console:
1. Open your Product Instance on [Setu Bridge](https://bridge.setu.co/).
2. Navigate to **Webhooks / Notifications**.
3. Configure the **Notification URL**:
   `https://caused-possibilities-mount-costume.trycloudflare.com/api/v1/payments/setu/notifications`
4. Setu will send HTTP POST requests with:
   - Header: `x-setu-signature`
   - Algorithm: HMAC-SHA256 of the raw body using `SETU_WEBHOOK_SECRET`.
5. For redirects, use the callback base URL:
   `https://caused-possibilities-mount-costume.trycloudflare.com/api/v1/payments/setu/callback`

---

## 6. Testing the Payment Flow

### Step 1: Create Contribution Intent
1. Open TripCrew and navigate to your Trip Workspace -> **TripCrew Pay**.
2. Tap **Add Your Share**.
3. Enter contribution amount (e.g. ₹5,000).
4. TripCrew calculates:
   - Contribution: ₹5,000 (500,000 paise)
   - 1% Platform Fee: ₹50 (5,000 paise)
   - Total Charge: ₹5,050 (505,000 paise)
5. Tap **Add Contribution via UPI**.
6. The app contacts the backend and receives the Setu UPI payment link and intent URL.

### Step 2: Complete or Simulate Payment
- **In Setu Sandbox Console**:
  - Setu Bridge provides mock trigger actions under **Simulate Payment** or **Trigger Funds** to mark payment links as paid or failed.
- **In TripCrew UI**:
  - Tap **Refresh / Check Status** to query the payment link status directly from Setu UAT.
  - When Setu reports `PAYMENT_SUCCESSFUL` / `payment.success`:
    - The backend finalizes the contribution atomically.
    - Exactly ₹5,000 is credited to the Trip Pot balance.
    - The ₹50 fee is tracked in transaction metadata.
    - The payment sheet transitions to **Payment Confirmed • Money Added**.

### Step 3: Test Failure & Cancellation
- In Setu Bridge, trigger a simulated decline or timeout.
- In TripCrew, tap **Refresh / Check Status**.
- Status updates to `FAILED` or `EXPIRED`.
- The Trip Pot balance remains completely unchanged.

### Step 4: Test App Restart Recovery
1. Start a contribution intent.
2. Force close TripCrew while in `WAITING FOR PAYMENT`.
3. Complete or cancel the payment in Setu Bridge console.
4. Reopen TripCrew.
5. `recoverPendingPayments()` automatically checks the unresolved attempt with Setu and reconciles the state.

---

## 7. How to Switch Back to Default Sandbox Simulator

To revert to the internal sandbox simulator without requiring Setu credentials:

1. In `.env`:
   ```env
   PAYMENT_PROVIDER=sandbox
   ```
2. Or pass the dart compile flag:
   ```bash
   flutter run --dart-define=PAYMENT_PROVIDER=sandbox
   ```
3. Or in developer settings in the app, select **Sandbox Simulator**.

When in `sandbox` mode, the app uses `SandboxPaymentProvider`, enabling one-tap simulation of Success, Decline, and Timeout without external network dependencies.
