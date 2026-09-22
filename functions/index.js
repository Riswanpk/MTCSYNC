const admin = require("firebase-admin");

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2/options");
const { onSchedule } = require("firebase-functions/v2/scheduler");

admin.initializeApp();

// Set default region
setGlobalOptions({ region: "asia-south1" });

exports.deleteUserFromAuth = onCall(async (request) => {
  const context = request.auth;
  const data = request.data;

  // Verify authentication
  if (!context) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const { uid } = data;

  // Validate uid
  if (!uid || typeof uid !== "string" || uid.trim() === "") {
    throw new HttpsError("invalid-argument", "uid must be a non-empty string.");
  }

  // Prevent self-deletion
  if (context.uid === uid) {
    throw new HttpsError("permission-denied", "Users cannot delete themselves.");
  }

  try {
    // Delete from Firebase Auth
    await admin.auth().deleteUser(uid);

    // Optional Firestore cleanup
    await admin.firestore().collection("users").doc(uid).delete();

    return {
      success: true,
      message: `User ${uid} deleted successfully.`,
    };
  } catch (error) {
    console.error("Error deleting user:", error);
    throw new HttpsError("internal", error.message);
  }
});

exports.sendDailyTodoReport = require("./sendDailyTodoReport").sendDailyTodoReport;

// Customer Individual Report Functions
const customerIndividual = require("./CustomerIndividual");
exports.sendCustomerIndividualReport = customerIndividual.sendCustomerIndividualReport;
exports.triggerCustomerIndividualReport = customerIndividual.triggerCustomerIndividualReport;
exports.resetCustomerTargetsMonthly = customerIndividual.resetCustomerTargetsMonthly;



/**
 * Callable: Sends an FCM push notification to the assigned user's device.
 * invoker: 'public' lets the Firebase SDK pass calls through at the
 * Cloud Run level while request.auth still enforces Firebase Auth.
 */
exports.sendLeadAssignmentNotification = onCall(
  { invoker: "public" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated.");
    }

    const { recipientUid, title, body, leadDocId, leadName, reminderAt } = request.data;

    if (!recipientUid || typeof recipientUid !== "string") {
      throw new HttpsError("invalid-argument", "recipientUid is required.");
    }

    // Retrieve the recipient's FCM token from their Firestore user document
    const userSnap = await admin.firestore().collection("users").doc(recipientUid).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Recipient user document not found.");
    }

    const fcmToken = userSnap.data().fcm_token;
    if (!fcmToken) {
      throw new HttpsError("not-found", "Recipient has no FCM token. They may need to log in again.");
    }

    const { notifType, complaintId } = request.data;
    const dataPayload = {
      type: notifType ?? "sme_lead_assignment",
      leadDocId: leadDocId ?? "",
      leadName: leadName ?? "",
      complaintId: complaintId ? String(complaintId) : (leadDocId ? String(leadDocId) : ""),
    };
    if (reminderAt != null) {
      dataPayload.reminderAt = String(reminderAt);
    }

    let channelId = "basic_channel_v2";
    let soundName = "leadsreminder";

    if (notifType === "customer_editing_request" || notifType === "customer_deletion_request" || notifType === "customer_approval") {
      channelId = "customer_approval_channel";
      soundName = "default";
    } else if (notifType === "dme_request_raised" || notifType === "dme_request") {
      channelId = "dme_requests_channel";
      soundName = "you_have_a_request";
    } else if (notifType === "dme_request_approved") {
      channelId = "dme_requests_approved_channel";
      soundName = "request_has_been_approved";
    } else if (notifType === "dme_request_rejected") {
      channelId = "dme_requests_rejected_channel";
      soundName = "request_has_been_rejected";
    } else if (notifType === "sme_lead_assignment" || notifType === "sme_lead") {
      channelId = "sme_lead_channel";
      soundName = "sme_leads_assigned";
    } else if (notifType === "core_task_completion") {
      channelId = "task_completion_channel";
      soundName = "task_completed";
    } else if (notifType === "core_task_assignment") {
      channelId = "task_assignment_channel";
      soundName = "you_have_been_assigned_a_task";
    } else if (notifType === "complaint_resolved" || notifType === "dme_complaint_resolved") {
      channelId = "dme_complaints_resolved_channel";
      soundName = "complaint_resolved";
    } else if (notifType === "complaint_review_pending" || notifType === "complaint_action_taken" || notifType === "dme_complaint_review_pending") {
      channelId = "dme_complaints_review_channel";
      soundName = "complaint_review_pending";
    } else if (notifType === "dme_complaint" || notifType === "complaint_raised" || notifType === "complaint_assigned") {
      channelId = "dme_complaints_channel";
      soundName = "complaint_raised";
    } else if (notifType === "todo" || notifType === "todo_reminder") {
      channelId = "todo_reminder_channel";
      soundName = "todo_reminder";
    } else if (notifType === "todos_pending" || notifType === "pending_todos") {
      channelId = "todos_pending_channel";
      soundName = "you_have_todos_pending";
    }

    const message = {
      token: fcmToken,
      notification: {
        title: title ?? "New Lead Assigned",
        body: body ?? "A new lead has been assigned to you.",
      },
      data: dataPayload,
      android: {
        priority: "high",
        notification: {
          channelId: channelId,
          ...(soundName === "default" ? { defaultSound: true } : { sound: soundName }),
        },
      },
      apns: {
        payload: {
          aps: { sound: soundName === "default" ? "default" : `${soundName}.aiff` },
        },
      },
    };

    await admin.messaging().send(message);
    return { success: true };
  }
);







