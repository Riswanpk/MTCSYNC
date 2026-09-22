const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const moment = require("moment-timezone");

// Only initialize if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

// Helper: Get month name
const getMonthName = (month) => {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];
  return months[month - 1];
};

// Helper: Get month-year string (e.g., "Feb 2026")
const getMonthYear = (date) => {
  return `${getMonthName(date.month() + 1)} ${date.year()}`;
};

/**
 * Scheduled function to create new month's customer list from previous month
 * Runs on the 1st of every month at 12:01 AM IST
 * Copies: name, contacts, address
 * lastRemarks = previous month's remarks (for reference)
 * remarks = empty (fresh for new month)
 * callMade = false (fresh start)
 */
exports.resetCustomerTargetsMonthly = onSchedule(
  {
    schedule: "1 0 1 * *", // 1st day of month, 12:01 AM
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
  },
  async (event) => {
    const now = moment().tz("Asia/Kolkata");
    const prev = now.clone().subtract(1, "month");
    const prevMonthYear = getMonthYear(prev);
    const currMonthYear = getMonthYear(now);

    console.log(`Creating new customer list: ${prevMonthYear} -> ${currMonthYear}`);

    try {
      const prevUsersRef = admin.firestore()
        .collection("customer_target")
        .doc(prevMonthYear)
        .collection("users");

      const currUsersRef = admin.firestore()
        .collection("customer_target")
        .doc(currMonthYear)
        .collection("users");

      const prevUsersSnapshot = await prevUsersRef.get();

      if (prevUsersSnapshot.empty) {
        console.log(`No data found for ${prevMonthYear}`);
        return null;
      }

      let batch = admin.firestore().batch();
      let batchCount = 0;

      for (const userDoc of prevUsersSnapshot.docs) {
        // Normalize doc ID to lowercase to prevent case-mismatch duplicates
        const normalizedId = userDoc.id.toLowerCase();

        let existingCurrCustomers = [];
        let currData = {};
        
        // Check if current month already has data for this user
        const currDoc = await currUsersRef.doc(normalizedId).get();
        if (currDoc.exists) {
          currData = currDoc.data();
          existingCurrCustomers = currData.customers || [];
          console.log(`User ${normalizedId} already has data for ${currMonthYear}, merging previous month's data...`);
        } else {
          console.log(`Creating new target for User ${normalizedId} in ${currMonthYear}`);
        }

        const prevData = userDoc.data();
        const prevCustomers = prevData.customers || [];

        // Create new customer list from previous month
        const newCustomersFromPrev = prevCustomers.map((customer) => ({
          name: customer.name || "",
          contact1: customer.contact1 || customer.contact || "",
          contact2: customer.contact2 || "",
          address: customer.address || "",
          lastRemarks: customer.remarks || "", // Previous month's remarks (read-only)
          remarks: "", // Fresh for new month
          callMade: false, // Fresh start for new month
        }));

        // Merge with existing curr customers (if any) to preserve manually imported ones
        // Ensure no duplicates by matching name and contact1
        const normalizeKey = (c) => `${(c.name || "").toLowerCase().trim()}_${(c.contact1 || c.contact || "").trim()}`;
        const existingKeys = new Set(existingCurrCustomers.map(normalizeKey));
        
        const mergedCustomers = [...existingCurrCustomers];
        for (const c of newCustomersFromPrev) {
          if (!existingKeys.has(normalizeKey(c))) {
            mergedCustomers.push(c);
          }
        }

        const newData = {
          branch: currData.branch || prevData.branch || "",
          user: (currData.user || prevData.user || userDoc.id).toLowerCase(),
          customers: mergedCustomers,
          updated: admin.firestore.FieldValue.serverTimestamp(),
        };

        batch.set(currUsersRef.doc(normalizedId), newData);
        batchCount++;

        // Firestore batch limit is 500; commit and start a fresh batch
        if (batchCount >= 400) {
          await batch.commit();
          batch = admin.firestore().batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      console.log(`Customer list created successfully for ${currMonthYear}`);
      return null;
    } catch (error) {
      console.error("Error creating customer list:", error);
      throw error;
    }
  }
);

module.exports = exports;
