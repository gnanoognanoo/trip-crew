/**
 * TripCrew Trusted Payment Backend Service (Setu UPI UAT Implementation)
 *
 * Runs as an external free-tier backend to protect payment secrets
 * under Firebase Spark tier constraints.
 *
 * Routes:
 * - GET  /health                                -> Service health and configuration check
 * - GET  /api/v1/payments/setu                  -> Setu callback base info
 * - GET  /api/v1/payments/setu/callback         -> Browser redirect callback handler
 * - POST /api/v1/payments/setu/notifications    -> Setu webhook notification endpoint
 * - POST /api/v1/payments/setu/webhook          -> Alias for notifications
 * - POST /api/v1/payments/setu/intent           -> Create payment intent with Setu UAT
 * - GET  /api/v1/payments/setu/status/:id       -> Fetch status for a payment
 */

const express = require('express');
const crypto = require('crypto');
const http = require('https');
const fs = require('fs');
const path = require('path');

// Automatically load .env file if present
const envCandidates = [
  path.join(__dirname, '.env'),
  path.join(__dirname, '..', '.env')
];

for (const envPath of envCandidates) {
  if (fs.existsSync(envPath)) {
    try {
      if (typeof process.loadEnvFile === 'function') {
        process.loadEnvFile(envPath);
      } else {
        const envContent = fs.readFileSync(envPath, 'utf8');
        envContent.split('\n').forEach(line => {
          const match = line.match(/^\s*([\w.-]+)\s*=\s*(.*)?\s*$/);
          if (match && !process.env[match[1]]) {
            process.env[match[1]] = (match[2] || '').trim().replace(/^['"]|['"]$/g, '');
          }
        });
      }
      break;
    } catch (_) {}
  }
}

const app = express();
const PORT = process.env.PORT || 8080;

// Configuration
const SETU_ENV = process.env.SETU_ENVIRONMENT || 'uat';
const SETU_BASE_URL = SETU_ENV === 'production' 
  ? 'https://prod.setu.co/api/v2' 
  : 'https://uat.setu.co/api/v2';
const SETU_AUTH_URL = 'https://accountservice.setu.co/v1/users/login';

const SETU_CLIENT_ID = process.env.SETU_CLIENT_ID || '';
const SETU_CLIENT_SECRET = process.env.SETU_CLIENT_SECRET || '';
const SETU_PRODUCT_INSTANCE_ID = process.env.SETU_PRODUCT_INSTANCE_ID || '';
const SETU_WEBHOOK_SECRET = process.env.SETU_WEBHOOK_SECRET || '';

// UPI Setu (uMap) Configuration
const SETU_UMAP_BASE_URL = 'https://umap.setu.co/api';
const SETU_MERCHANT_ID = process.env.SETU_MERCHANT_ID || '';
const SETU_MERCHANT_VPA = process.env.SETU_MERCHANT_VPA || '';
const SETU_CUSTOMER_VPA = process.env.SETU_CUSTOMER_VPA || '';
const SETU_PRODUCT_CONFIG_ID = process.env.SETU_PRODUCT_CONFIG_ID || process.env.SETU_PRODUCT_INSTANCE_ID || '';

// Token Cache
let cachedToken = null;
let tokenExpiresAt = 0;

// Processed Webhooks Store (In-Memory Idempotency Cache)
const processedWebhooks = new Set();

// Capture RAW body for accurate webhook signature verification
app.use(express.json({
  verify: (req, res, buf) => {
    req.rawBody = buf.toString('utf8');
  }
}));

// CORS middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, x-setu-signature, X-Setu-Product-Instance-ID');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

/**
 * Validates whether Setu credentials exist.
 */
function isConfigured() {
  return Boolean(
    SETU_CLIENT_ID && 
    SETU_CLIENT_SECRET && 
    SETU_PRODUCT_INSTANCE_ID
  );
}

/**
 * Obtains OAuth Bearer token from Setu Bridge.
 */
async function getSetuToken() {
  const now = Date.now();
  if (cachedToken && now < tokenExpiresAt - 60000) {
    return cachedToken;
  }

  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      clientID: SETU_CLIENT_ID,
      secret: SETU_CLIENT_SECRET,
      grant_type: 'client_credentials'
    });

    const url = new URL(SETU_AUTH_URL);
    const req = http.request({
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'client': 'bridge',
        'Content-Length': Buffer.byteLength(postData)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            const data = JSON.parse(body);
            cachedToken = data.token || data.access_token;
            const expiresInSec = data.expires_in || 1800;
            tokenExpiresAt = Date.now() + (expiresInSec * 1000);
            resolve(cachedToken);
          } else {
            reject(new Error(`Setu auth failed: HTTP ${res.statusCode} - ${body}`));
          }
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

/**
 * Constant-time comparison for HMAC signature verification.
 */
function verifyHmacSignature(rawBody, secret, signature) {
  if (!secret || !signature || !rawBody) return false;

  const hmac = crypto.createHmac('sha256', secret);
  hmac.update(rawBody);
  const digestHex = hmac.digest('hex').toLowerCase();
  
  const hmacB64 = crypto.createHmac('sha256', secret);
  hmacB64.update(rawBody);
  const digestB64 = hmacB64.digest('base64');

  const cleanSig = signature.trim();

  try {
    if (cleanSig.length === digestHex.length) {
      return crypto.timingSafeEqual(
        Buffer.from(cleanSig.toLowerCase()), 
        Buffer.from(digestHex)
      );
    }
    if (cleanSig.length === digestB64.length) {
      return crypto.timingSafeEqual(
        Buffer.from(cleanSig), 
        Buffer.from(digestB64)
      );
    }
    return false;
  } catch (_) {
    return false;
  }
}

// -----------------------------------------------------------------------------
// ENDPOINTS
// -----------------------------------------------------------------------------

// Health check & status
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    environment: SETU_ENV,
    isConfigured: isConfigured(),
    message: isConfigured() 
      ? 'Setu UPI UAT Backend Ready' 
      : 'WAITING FOR SETU CREDENTIALS'
  });
});

// SETU_CALLBACK_BASE_URL: GET /api/v1/payments/setu
app.get('/api/v1/payments/setu', (req, res) => {
  res.json({
    status: 'ok',
    service: 'TripCrew Setu UPI UAT Backend',
    environment: SETU_ENV,
    isConfigured: isConfigured(),
    clientIdPrefix: SETU_CLIENT_ID ? SETU_CLIENT_ID.substring(0, 8) + '...' : null,
    productInstanceId: SETU_PRODUCT_INSTANCE_ID || null,
    callbackBaseUrl: '/api/v1/payments/setu',
    notificationEndpoint: '/api/v1/payments/setu/notifications'
  });
});

// Browser redirect callback: GET /api/v1/payments/setu/callback
app.get('/api/v1/payments/setu/callback', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>TripCrew Pay - Setu UAT Callback</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; text-align: center; padding: 40px 20px; background: #f8fafc; }
          .card { max-width: 420px; margin: 0 auto; background: white; padding: 32px; border-radius: 16px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
          .success-icon { font-size: 48px; color: #10b981; }
          h2 { margin: 16px 0 8px; color: #0f172a; }
          p { color: #64748b; font-size: 14px; line-height: 1.5; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="success-icon">✓</div>
          <h2>Payment Flow Finished</h2>
          <p>You can return to the TripCrew app. Your payment status will refresh automatically.</p>
        </div>
      </body>
    </html>
  `);
});

// Create Payment Intent (Client -> Backend -> Setu UAT Merchant Quickstart)
app.post('/api/v1/payments/setu/intent', async (req, res) => {
  if (!isConfigured()) {
    return res.status(503).json({
      error: 'UPI test provider is not configured.',
      configured: false
    });
  }

  try {
    const { 
      tripId, 
      uid, 
      amountPaise, 
      platformFeePaise, 
      totalChargePaise, 
      clientRequestId,
      amountValue,
      billerBillID,
      payeeName = 'TripCrew'
    } = req.body;

    const finalAmount = amountValue || totalChargePaise || (amountPaise ? amountPaise + (platformFeePaise || 0) : 10100);
    const finalBillId = billerBillID || clientRequestId || ('TC_UAT_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7));

    const token = await getSetuToken();

    const requestPayload = {
      amountValue: finalAmount,
      billerBillID: finalBillId,
      payeeName
    };

    const postData = JSON.stringify(requestPayload);
    const targetUrl = new URL('https://uatapi.setu.co/api/merchant/v2/collect');

    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'X-Setu-Product-Instance-ID': SETU_PRODUCT_INSTANCE_ID,
      'Content-Length': Buffer.byteLength(postData)
    };

    const makeRequest = (hostname) => {
      return new Promise((resolve) => {
        const sReq = http.request({
          hostname,
          port: 443,
          path: '/api/merchant/v2/collect',
          method: 'POST',
          headers
        }, (sRes) => {
          let body = '';
          sRes.on('data', c => body += c);
          sRes.on('end', () => resolve({ status: sRes.statusCode, body }));
        });

        sReq.on('error', (err) => resolve({ error: err.message, code: err.code }));
        sReq.write(postData);
        sReq.end();
      });
    };

    let result = await makeRequest(targetUrl.hostname);

    if (result.error) {
      return res.status(502).json({
        correctUatHost: 'https://uatapi.setu.co',
        billerBillID: finalBillId,
        error: result.error,
        code: result.code,
        platformBillID: null,
        shortURL: 'NOT CREATED',
        upiID: 'NOT CREATED',
        initialSetuStatus: 'NOT CREATED',
        paymentAttempt: 'pending',
        tripPotCredited: 0
      });
    }

    try {
      const data = JSON.parse(result.body);
      const platformBillID = data.platformBillID || data.id || null;
      const shortURL = data.shortURL || data.shortUrl || data.paymentUrl || null;
      const upiID = data.upiID || data.upiLink || null;
      const status = data.status || 'pending';

      return res.status(result.status || 200).json({
        correctUatHost: 'https://uatapi.setu.co',
        httpStatus: result.status,
        billerBillID: finalBillId,
        platformBillID: platformBillID || 'NOT CREATED',
        shortURL: shortURL ? 'CREATED' : 'NOT CREATED',
        upiID: upiID || 'NOT CREATED',
        initialSetuStatus: status,
        paymentAttempt: 'pending',
        tripPotCredited: 0,
        rawResponse: data
      });
    } catch (_) {
      return res.status(result.status || 500).json({
        correctUatHost: 'https://uatapi.setu.co',
        httpStatus: result.status,
        billerBillID: finalBillId,
        platformBillID: null,
        shortURL: 'NOT CREATED',
        upiID: 'NOT CREATED',
        initialSetuStatus: 'NOT CREATED',
        paymentAttempt: 'pending',
        tripPotCredited: 0,
        rawResponse: result.body
      });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Fetch Status (Client -> Backend -> Setu UAT)
app.get('/api/v1/payments/setu/status/:platformBillId', async (req, res) => {
  if (!isConfigured()) {
    return res.status(503).json({ error: 'UPI test provider is not configured.' });
  }

  try {
    const token = await getSetuToken();
    const url = new URL(`${SETU_BASE_URL}/payment-links/${req.params.platformBillId}`);

    const sReq = http.request({
      hostname: url.hostname,
      path: url.pathname,
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'X-Setu-Product-Instance-ID': SETU_PRODUCT_INSTANCE_ID
      }
    }, (sRes) => {
      let body = '';
      sRes.on('data', c => body += c);
      sRes.on('end', () => {
        try {
          const data = JSON.parse(body);
          res.status(sRes.statusCode).json(data);
        } catch (e) {
          res.status(502).json({ error: 'Invalid response from Setu', raw: body });
        }
      });
    });

    sReq.on('error', (err) => res.status(500).json({ error: err.message }));
    sReq.end();
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Create UPI Setu Merchant Quickstart Collect Request: POST /api/v1/payments/setu/collect
app.post('/api/v1/payments/setu/collect', async (req, res) => {
  if (!isConfigured()) {
    return res.status(503).json({ error: 'UPI test provider credentials are not configured.' });
  }

  try {
    const token = await getSetuToken();

    const { 
      amountValue = 10100, // ₹101 total (₹100 contribution + ₹1 fee) in integer paise
      billerBillID = 'TC_UAT_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7),
      payeeName = 'TripCrew',
      tripId = 'trip_goa_001', 
      uid = 'usr_test_001', 
      paymentAttemptId = 'att_' + Date.now()
    } = req.body;

    const requestPayload = {
      amountValue,
      billerBillID,
      payeeName
    };

    const postData = JSON.stringify(requestPayload);

    // Documented Setu Merchant Quickstart host
    const targetUrl = new URL('https://uatapi.setu.co/api/merchant/v2/collect');

    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'X-Setu-Product-Instance-ID': SETU_PRODUCT_INSTANCE_ID,
      'Content-Length': Buffer.byteLength(postData)
    };

    const makeRequest = (hostname) => {
      return new Promise((resolve) => {
        const sReq = http.request({
          hostname,
          port: 443,
          path: '/api/merchant/v2/collect',
          method: 'POST',
          headers
        }, (sRes) => {
          let body = '';
          sRes.on('data', c => body += c);
          sRes.on('end', () => resolve({ status: sRes.statusCode, body }));
        });

        sReq.on('error', (err) => resolve({ error: err.message, code: err.code }));
        sReq.write(postData);
        sReq.end();
      });
    };

    // Attempt primary documented host: https://uatapi.setu.co
    let result = await makeRequest(targetUrl.hostname);

    if (result.error) {
      return res.status(502).json({
        correctUatHost: 'https://uatapi.setu.co',
        billerBillID,
        error: result.error,
        code: result.code,
        platformBillID: null,
        shortURL: 'NOT CREATED',
        upiID: 'NOT CREATED',
        initialSetuStatus: 'NOT CREATED',
        paymentAttempt: 'pending',
        tripPotCredited: 0
      });
    }

    try {
      const data = JSON.parse(result.body);
      const platformBillID = data.platformBillID || data.id || null;
      const shortURL = data.shortURL || data.shortUrl || data.paymentUrl || null;
      const upiID = data.upiID || data.upiLink || null;
      const status = data.status || 'pending';

      return res.status(result.status || 200).json({
        correctUatHost: 'https://uatapi.setu.co',
        httpStatus: result.status,
        billerBillID,
        platformBillID: platformBillID || 'NOT CREATED',
        shortURL: shortURL ? 'CREATED' : 'NOT CREATED',
        upiID: upiID || 'NOT CREATED',
        initialSetuStatus: status,
        paymentAttempt: 'pending',
        tripPotCredited: 0,
        rawResponse: data
      });
    } catch (_) {
      return res.status(result.status || 500).json({
        correctUatHost: 'https://uatapi.setu.co',
        httpStatus: result.status,
        billerBillID,
        platformBillID: null,
        shortURL: 'NOT CREATED',
        upiID: 'NOT CREATED',
        initialSetuStatus: 'NOT CREATED',
        paymentAttempt: 'pending',
        tripPotCredited: 0,
        rawResponse: result.body
      });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Check UPI Setu Collect Request Status: GET /api/v1/payments/setu/collect/:id
app.get('/api/v1/payments/setu/collect/:id', async (req, res) => {
  if (!isConfigured()) {
    return res.status(503).json({ error: 'UPI test provider is not configured.' });
  }

  try {
    const token = await getSetuToken();
    let tokenMerchantId = null;
    try {
      const parts = token.split('.');
      if (parts.length === 3) {
        const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));
        const adminRole = (payload.realm_access?.roles || []).find(r => r.startsWith('admin@'));
        if (adminRole) tokenMerchantId = adminRole.replace('admin@', '');
      }
    } catch (_) {}

    const merchantId = req.headers['merchantid'] || 
                       req.query.merchantId || 
                       SETU_MERCHANT_ID || 
                       tokenMerchantId;

    const url = new URL(`${SETU_UMAP_BASE_URL}/v1/merchants/collect/${req.params.id}`);
    const sReq = http.request({
      hostname: url.hostname,
      path: url.pathname,
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'merchantId': merchantId || ''
      }
    }, (sRes) => {
      let body = '';
      sRes.on('data', c => body += c);
      sRes.on('end', () => {
        try {
          const data = JSON.parse(body);
          res.status(sRes.statusCode).json(data);
        } catch (e) {
          res.status(sRes.statusCode).json({ raw: body });
        }
      });
    });

    sReq.on('error', (err) => res.status(500).json({ error: err.message }));
    sReq.end();
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Common handler for Setu webhook notifications (UPI Setu Product)
function handleSetuNotification(req, res) {
  const signature = req.headers['x-setu-signature'];
  
  // If webhook secret is configured, enforce cryptographic signature check
  if (SETU_WEBHOOK_SECRET && SETU_WEBHOOK_SECRET !== 'your_setu_webhook_secret_here') {
    if (!signature) {
      return res.status(401).json({ error: 'Missing x-setu-signature header.' });
    }

    const rawBody = req.rawBody || JSON.stringify(req.body);
    const isValid = verifyHmacSignature(rawBody, SETU_WEBHOOK_SECRET, signature);

    if (!isValid) {
      return res.status(401).json({ error: 'Invalid webhook signature.' });
    }
  }

  try {
    const payload = req.body || {};
    const eventType = payload.eventType || payload.event || payload.status || 'unknown';
    const data = payload.data || payload;

    const eventId = payload.eventId || data.txnId || data.transactionId || data.platformBillID || `${Date.now()}`;
    const txnId = data.txnId || data.transactionId || '';
    const merchantReferenceId = data.merchantReferenceId || payload.merchantReferenceId || data.billerBillID || '';
    const amount = data.amount !== undefined ? data.amount : (data.amountPaid || 0);
    const currency = data.currency || 'INR';
    const paymentStatus = data.paymentStatus || data.status || eventType;

    // Idempotency check: duplicate event receipt
    if (processedWebhooks.has(eventId)) {
      return res.status(200).json({ 
        status: 'acknowledged', 
        idempotent: true, 
        product: 'UPI SETU',
        eventType,
        eventId,
        message: 'Duplicate event already processed.' 
      });
    }
    processedWebhooks.add(eventId);

    // Keep cache bounded
    if (processedWebhooks.size > 10000) {
      const oldest = Array.from(processedWebhooks).slice(0, 2000);
      oldest.forEach(k => processedWebhooks.delete(k));
    }

    console.log(`[UPI Setu Webhook] Event: ${eventType} | Txn: ${txnId || 'N/A'} | Ref: ${merchantReferenceId || 'N/A'} | Status: ${paymentStatus} | Amount: ${amount}`);

    // Return 200 OK to Setu Bridge
    return res.status(200).json({ 
      status: 'received', 
      product: 'UPI SETU',
      eventType,
      eventId,
      txnId,
      merchantReferenceId,
      timestamp: new Date().toISOString()
    });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}

// Actual Setu UAT live probe endpoint (performs real call to Setu servers, zero mock)
app.post('/api/v1/payments/setu/uat-probe', async (req, res) => {
  if (!isConfigured()) {
    return res.status(503).json({ error: 'Setu UAT credentials not configured' });
  }

  try {
    const token = await getSetuToken();
    const tokenParts = token.split('.');
    let tokenExpiry = null;
    let clientIdInToken = null;
    if (tokenParts.length === 3) {
      try {
        const payload = JSON.parse(Buffer.from(tokenParts[1], 'base64').toString('utf8'));
        tokenExpiry = payload.exp ? new Date(payload.exp * 1000).toISOString() : null;
        clientIdInToken = payload.azp || payload.clientId;
      } catch (_) {}
    }

    return res.status(200).json({
      actualSetuUatCalled: true,
      product: 'UPI SETU',
      authServer: SETU_AUTH_URL,
      status: 'AUTHENTICATED_LIVE_UAT',
      tokenReceived: Boolean(token),
      tokenLength: token.length,
      clientIdInToken,
      tokenExpiry,
      productInstanceId: SETU_PRODUCT_INSTANCE_ID,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    return res.status(502).json({
      actualSetuUatCalled: true,
      error: 'Setu live UAT call failed',
      message: err.message
    });
  }
});

// SETU_NOTIFICATION_URL: POST /api/v1/payments/setu/notifications
app.post('/api/v1/payments/setu/notifications', handleSetuNotification);

// Alias: POST /api/v1/payments/setu/webhook
app.post('/api/v1/payments/setu/webhook', handleSetuNotification);

// Root route
app.get('/', (req, res) => {
  res.json({
    app: 'TripCrew Setu UPI UAT Backend',
    status: 'running',
    health: '/health',
    setuCallback: '/api/v1/payments/setu',
    setuNotifications: '/api/v1/payments/setu/notifications'
  });
});

// Start Server
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`TripCrew Setu UAT Backend running on port ${PORT}`);
    console.log(`Environment: ${SETU_ENV}`);
    console.log(`Configured: ${isConfigured() ? 'YES' : 'NO (Waiting for credentials)'}`);
  });
}

module.exports = {
  app,
  verifyHmacSignature,
  isConfigured
};
