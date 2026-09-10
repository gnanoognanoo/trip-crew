const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Callable Function: joinTripByCode
 * Safely resolves an invite code, prevents duplicate membership,
 * assigns role = 'member' (never client-chosen), and returns trip details.
 */
exports.joinTripByCode = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication is required to join a trip."
    );
  }

  const { inviteCode } = request.data || {};
  if (!inviteCode || typeof inviteCode !== "string") {
    throw new HttpsError(
      "invalid-argument",
      "A valid invite code must be provided."
    );
  }

  const normalizedCode = inviteCode.trim().toUpperCase();

  // Find invite code mapping
  const inviteDoc = await db.collection("tripInvites").doc(normalizedCode).get();
  if (!inviteDoc.exists) {
    throw new HttpsError(
      "not-found",
      "Invalid or expired trip invite code."
    );
  }

  const { tripId } = inviteDoc.data();
  const tripRef = db.collection("trips").doc(tripId);
  const tripDoc = await tripRef.get();

  if (!tripDoc.exists) {
    throw new HttpsError(
      "not-found",
      "The trip associated with this invite code was not found."
    );
  }

  const uid = request.auth.uid;
  const memberRef = tripRef.collection("members").doc(uid);

  // Use a transaction to safely handle membership
  const result = await db.runTransaction(async (transaction) => {
    const existingMember = await transaction.get(memberRef);

    if (existingMember.exists) {
      return {
        alreadyMember: true,
        tripId,
        tripName: tripDoc.data().name || "Trip",
      };
    }

    // Fetch user profile display name if available
    const userDoc = await transaction.get(db.collection("users").doc(uid));
    const displayName =
      userDoc.exists && userDoc.data().name
        ? userDoc.data().name
        : request.auth.token.name || "Member";
    const photoUrl = userDoc.exists ? userDoc.data().photoUrl : null;

    // Enforce role = 'member' (never allow caller to elevate to 'owner')
    transaction.set(memberRef, {
      uid,
      displayName,
      photoUrl: photoUrl || null,
      role: "member",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      isOnline: true,
    });

    transaction.update(tripRef, {
      memberCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      alreadyMember: false,
      tripId,
      tripName: tripDoc.data().name || "Trip",
    };
  });

  return {
    success: true,
    ...result,
  };
});

/**
 * Callable Function: calculateSettlements
 * Computes minimal peer-to-peer settlement transactions for a trip.
 */
exports.calculateSettlements = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const { tripId } = request.data || {};
  if (!tripId) {
    throw new HttpsError("invalid-argument", "tripId is required.");
  }

  // Verify caller is a member
  const memberCheck = await db
    .collection("trips")
    .doc(tripId)
    .collection("members")
    .doc(request.auth.uid)
    .get();

  if (!memberCheck.exists) {
    throw new HttpsError("permission-denied", "You are not a member of this trip.");
  }

  const expensesSnapshot = await db
    .collection("trips")
    .doc(tripId)
    .collection("expenses")
    .get();

  const membersSnapshot = await db
    .collection("trips")
    .doc(tripId)
    .collection("members")
    .get();

  const memberNames = {};
  membersSnapshot.forEach((doc) => {
    memberNames[doc.id] = doc.data().displayName || "Member";
  });

  const netBalances = {};
  Object.keys(memberNames).forEach((mId) => {
    netBalances[mId] = 0;
  });

  expensesSnapshot.forEach((doc) => {
    const expense = doc.data();
    const participants =
      Array.isArray(expense.participantUids) && expense.participantUids.length > 0
        ? expense.participantUids
        : Object.keys(memberNames);

    if (participants.length === 0) return;

    const amountPaise = expense.amountPaise || 0;
    const share = Math.round(amountPaise / participants.length);

    netBalances[expense.paidByUid] = (netBalances[expense.paidByUid] || 0) + amountPaise;

    participants.forEach((pUid) => {
      netBalances[pUid] = (netBalances[pUid] || 0) - share;
    });
  });

  const creditors = [];
  const debtors = [];

  Object.entries(netBalances).forEach(([mUid, balance]) => {
    if (balance > 100) {
      creditors.push({ uid: mUid, balance });
    } else if (balance < -100) {
      debtors.push({ uid: mUid, balance: -balance });
    }
  });

  creditors.sort((a, b) => b.balance - a.balance);
  debtors.sort((a, b) => b.balance - a.balance);

  const transactions = [];
  let cIdx = 0;
  let dIdx = 0;

  while (cIdx < creditors.length && dIdx < debtors.length) {
    const creditor = creditors[cIdx];
    const debtor = debtors[dIdx];
    const settle = Math.min(creditor.balance, debtor.balance);

    if (settle > 0) {
      transactions.push({
        fromUid: debtor.uid,
        fromName: memberNames[debtor.uid] || "Member",
        toUid: creditor.uid,
        toName: memberNames[creditor.uid] || "Member",
        amountPaise: settle,
      });
    }

    creditor.balance -= settle;
    debtor.balance -= settle;

    if (creditor.balance === 0) cIdx++;
    if (debtor.balance === 0) dIdx++;
  }

  return { transactions };
});

/**
 * Callable Function: processTripCrewFee
 * Calculates 1% platform service fee abstraction on settlement transactions.
 */
exports.processTripCrewFee = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const { amountPaise } = request.data || {};
  if (typeof amountPaise !== "number" || amountPaise <= 0) {
    throw new HttpsError("invalid-argument", "Valid amountPaise is required.");
  }

  // 1% platform service fee
  const feePaise = Math.round(amountPaise * 0.01);
  const totalPaise = amountPaise + feePaise;

  return {
    baseAmountPaise: amountPaise,
    feePaise,
    totalPaise,
    feePercentage: 0.01,
    mode: "sandbox",
  };
});
