# TripCrew Pay — Razorpay Setup & Integration Guide

This guide details how to configure and test Razorpay Integration with TripCrew Pay under Firebase Spark tier constraints.

---

## 1. Overview & Trust Architecture

TripCrew Pay separates the payment journey into distinct trust domains:

```
[Flutter Client] 
      │  (No secrets, user requests contribution)
      ▼
[Trusted TripCrew Backend]
      │  (Holds Razorpay Key Secret & Webhook Secret)
      ▼
[Razorpay REST Gateway (https://api.razorpay.com/v1)]
      │  (Issues Razorpay Order ID & payment links)
      ▼
[Razorpay Payment Flow / Checkout]
      │
      ▼
[Razorpay Webhook / Notification with x-razorpay-signature]
      │
      ▼
[Trusted TripCrew Backend]
      │  (Verifies HMAC-SHA256 order_id|payment_id, matches exact amount + 1% fee, checks idempotency)
      ▼
[Firestore Immutable Ledger & Trip Pot Balance]
      │  (Realtime sync across all crew members)
      ▼
[All Crew Members See Updated Trip Pot]
```

---

## 2. Razorpay Developer Account & Credentials

1. **Sign Up / Log In**:
   - Go to [https://dashboard.razorpay.com/](https://dashboard.razorpay.com/) and create/access your account.
2. **Switch to Test Mode**:
   - In the top bar, toggle to **Test Mode**.
3. **Obtain API Keys**:
   - Go to **Account & Settings** -> **API Keys**.
   - Generate Key ID & Key Secret:
     - `RAZORPAY_KEY_ID` (starts with `rzp_test_...` or `rzp_live_...`)
     - `RAZORPAY_KEY_SECRET`
4. **Configure Webhooks**:
   - Under **Account & Settings** -> **Webhooks**, click **Add New Webhook**.
   - Webhook URL: `https://<your-backend-domain>/api/v1/payments/razorpay/notifications`
   - Secret: Set a strong `RAZORPAY_WEBHOOK_SECRET`.
   - Events: Select `payment.captured`, `payment.authorized`, `payment.failed`, `order.paid`.

> [!CAUTION]
> **Zero Secrets in Flutter**:
> Never put `RAZORPAY_KEY_SECRET` or `RAZORPAY_WEBHOOK_SECRET` inside Flutter client code or git repositories. They belong exclusively in backend environment variables.

---

## 3. Environment Variables Configuration

Copy `.env.example` to your backend environment:

```bash
cp .env.example .env
```

Populate the variables with your values from Razorpay Dashboard:

```env
# Provider Engine Selection ('sandbox' or 'razorpay')
PAYMENT_PROVIDER=razorpay

# Razorpay Settings
RAZORPAY_ENVIRONMENT=test
RAZORPAY_KEY_ID=rzp_test_your_key_id_here
RAZORPAY_KEY_SECRET=your_razorpay_key_secret_here
RAZORPAY_WEBHOOK_SECRET=your_razorpay_webhook_secret_here

# URL where trusted backend is hosted (e.g. Render, Cloudflare Workers, or local server)
TRIPCREW_BACKEND_URL=https://trip-creww-production.up.railway.app
```

---

## 4. Running the Trusted Backend Service

Because TripCrew remains on Firebase Spark tier (free tier), backend operations execute via a lightweight Node.js/Express server (`server/razorpay_backend_service.js`):

```bash
cd server
npm install express
# Set environment variables and start server
PORT=8080 node razorpay_backend_service.js
```

Verify the health check:
```bash
curl https://trip-creww-production.up.railway.app/health
```

Expected output:
```json
{
  "status": "ok",
  "environment": "test",
  "isConfigured": true,
  "message": "Razorpay Backend Service Ready"
}
```

---

## 5. Webhook & Callback Configuration

Configure your public endpoint in Razorpay Dashboard:

- **`SETU_NOTIFICATION_URL` / `RAZORPAY_NOTIFICATION_URL`**:
  `https://<your-domain>/api/v1/payments/razorpay/notifications`
- Razorpay sends HTTP POST requests with:
  - Header: `x-razorpay-signature`
  - Signature Algorithm: HMAC-SHA256 of the raw body using `RAZORPAY_WEBHOOK_SECRET`.

---

## 6. Testing the Payment Flow

### Step 1: Create Contribution Intent (Razorpay Order)
1. Open TripCrew and navigate to your Trip Workspace -> **TripCrew Pay**.
2. Tap **Add Your Share**.
3. Enter contribution amount (e.g. ₹5,000).
4. TripCrew calculates:
   - Contribution: ₹5,000 (500,000 paise)
   - 1% Platform Fee: ₹50 (5,000 paise)
   - Total Charge: ₹5,050 (505,000 paise)
5. Tap **Add Contribution via UPI / Razorpay**.
6. The app contacts the backend and receives the Razorpay Order ID.

### Step 2: Complete Payment
- On checkout success, signature `HMAC_SHA256(order_id + "|" + payment_id, secret)` is verified.
- The backend finalizes the contribution atomically:
  - Exactly ₹5,000 is credited to the Trip Pot balance.
  - The ₹50 fee is tracked in transaction metadata.
  - The payment sheet transitions to **Payment Confirmed • Money Added**.

---

## 7. Switching Back to Sandbox Simulator

To revert to the internal sandbox simulator without requiring external credentials:

1. In `.env`:
   ```env
   PAYMENT_PROVIDER=sandbox
   ```
2. Or pass the dart compile flag:
   ```bash
   flutter run --dart-define=PAYMENT_PROVIDER=sandbox
   ```
