// testDailyReport.js
// Temporary test runner for the Daily Todo & Leads report function.
//
// Usage option 1 (Local via Node):
//   1. Download your service account key JSON from Firebase Console:
//      Project Settings -> Service accounts -> Generate new private key
//   2. Save it as `serviceAccountKey.json` in this functions folder, or set:
//      $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\serviceAccountKey.json"
//   3. Run:
//      node testDailyReport.js
//      (Add --send-email to also send the test email)
//
// Usage option 2 (Firebase onCall trigger - already deployed):
//   Call `triggerDailyTodoReport` from Flutter / Postman / Firebase console.

const admin = require("firebase-admin");
const moment = require("moment-timezone");
const ExcelJS = require("exceljs");
const fs = require("fs");
const path = require("path");

// Look for local service account key if present
const keyPath = path.join(__dirname, "serviceAccountKey.json");
if (!admin.apps.length) {
  if (fs.existsSync(keyPath)) {
    const serviceAccount = require(keyPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log("Initialized Firebase Admin using serviceAccountKey.json");
  } else {
    admin.initializeApp();
  }
}


async function testDailyTodoReport({ sendEmail = false, targetEmail = "crmmalabar@gmail.com" } = {}) {
  console.log("=== Testing Daily Todo & Leads Report Function ===");
  
  const now = moment().tz("Asia/Kolkata");
  const yesterday = now.clone().subtract(1, "day");

  console.log(`Current IST Time: ${now.format("YYYY-MM-DD HH:mm:ss")}`);
  console.log(`Day of week: ${now.format("dddd")} (isoWeekday: ${now.isoWeekday()})`);

  let start, end;
  if (now.isoWeekday() === 1) { // Monday
    const saturday = now.clone().subtract(2, "days");
    start = saturday.clone().hour(12).minute(0).second(0).millisecond(0);
    end = now.clone().hour(12).minute(0).second(0).millisecond(0);
  } else {
    start = yesterday.clone().hour(12).minute(0).second(0).millisecond(0);
    end = now.clone().hour(12).minute(0).second(0).millisecond(0);
  }

  console.log(`Calculated Interval: ${start.format("YYYY-MM-DD HH:mm:ss")} to ${end.format("YYYY-MM-DD HH:mm:ss")}`);

  try {
    // 1. Fetch users
    console.log("\n1. Fetching users from Firestore...");
    const usersSnap = await admin.firestore().collection("users").get();
    const userMap = {};
    usersSnap.forEach(doc => {
      userMap[doc.id] = { ...doc.data(), uid: doc.id };
    });
    console.log(`   Found ${Object.keys(userMap).length} users.`);

    // 2. Build email and username lookups
    const emailToUserId = {};
    const usernameToUserId = {};
    for (const uid in userMap) {
      if (userMap[uid].email) {
        emailToUserId[userMap[uid].email.trim().toLowerCase()] = uid;
      }
      if (userMap[uid].username) {
        usernameToUserId[userMap[uid].username.trim().toLowerCase()] = uid;
      }
    }

    // 3. Prepare user status per branch
    const branchUserStatus = {};
    for (const userId in userMap) {
      const user = userMap[userId];
      const branch = user.branch || "Unknown";
      if (!branchUserStatus[branch]) branchUserStatus[branch] = {};
      branchUserStatus[branch][userId] = {
        lead: false,
        todo: false,
        username: user.username || user.email || "Unknown"
      };
    }

    // 4. Fetch follow_ups
    console.log("\n2. Fetching follow_ups in interval...");
    const followUpsSnap = await admin.firestore()
      .collection("follow_ups")
      .where("created_at", ">=", admin.firestore.Timestamp.fromDate(start.toDate()))
      .where("created_at", "<", admin.firestore.Timestamp.fromDate(end.toDate()))
      .get();
    console.log(`   Found ${followUpsSnap.size} follow_up documents.`);

    let matchedLeads = 0;
    followUpsSnap.forEach(doc => {
      const data = doc.data();
      let userId = data.created_by || data.userId || data.user_id;
      if ((!userId || !userMap[userId]) && data.email) {
        userId = emailToUserId[data.email.trim().toLowerCase()];
      }
      if ((!userId || !userMap[userId]) && (data.username || data.user_name || data.created_by_name)) {
        const name = (data.username || data.user_name || data.created_by_name).trim().toLowerCase();
        userId = usernameToUserId[name];
      }
      if (userId && userMap[userId]) {
        const branch = userMap[userId].branch || "Unknown";
        if (branchUserStatus[branch] && branchUserStatus[branch][userId]) {
          branchUserStatus[branch][userId].lead = true;
          matchedLeads++;
        }
      }
    });
    console.log(`   Matched leads for active users: ${matchedLeads}`);

    // 5. Fetch todos
    console.log("\n3. Fetching todos in interval...");
    const todosByUser = {};
    const todosSnap = await admin.firestore()
      .collection("todo")
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(start.toDate()))
      .where("timestamp", "<", admin.firestore.Timestamp.fromDate(end.toDate()))
      .get();
    console.log(`   Found ${todosSnap.size} todo documents.`);

    let matchedTodos = 0;
    todosSnap.forEach(doc => {
      const data = doc.data();
      let userId = data.created_by || data.userId || data.user_id;
      if ((!userId || !userMap[userId]) && data.email) {
        userId = emailToUserId[data.email.trim().toLowerCase()];
      }
      if ((!userId || !userMap[userId]) && (data.username || data.user_name || data.created_by_name)) {
        const name = (data.username || data.user_name || data.created_by_name).trim().toLowerCase();
        userId = usernameToUserId[name];
      }

      if (userId && userMap[userId]) {
        const branch = userMap[userId].branch || "Unknown";
        if (branchUserStatus[branch] && branchUserStatus[branch][userId]) {
          branchUserStatus[branch][userId].todo = true;
          matchedTodos++;
        }
        if (!todosByUser[userId]) {
          todosByUser[userId] = [];
        }
        todosByUser[userId].push({
          title: data.title || data.text || "",
          description: data.description || "",
          priority: data.priority || "High",
          status: data.status || "pending",
          assigned_to_name: data.assigned_to_name || null,
          assigned_by_name: data.assigned_by_name || null,
        });
      }
    });
    console.log(`   Matched todos for active users: ${matchedTodos}`);

    // 6. Generate Excel workbook
    console.log("\n4. Generating Excel workbook...");
    const workbook = new ExcelJS.Workbook();
    workbook.creator = "MTC Sync";
    workbook.created = new Date();

    const sortedBranches = Object.keys(branchUserStatus).sort();
    let totalRowsGenerated = 0;
    let totalTodosDetailed = 0;

    for (const branch of sortedBranches) {
      const sheet = workbook.addWorksheet(branch.substring(0, 31));

      // Style header
      sheet.columns = [
        { header: "Username", key: "username", width: 25 },
        { header: "Leads", key: "lead", width: 12 },
        { header: "Todo", key: "todo", width: 12 },
      ];

      sheet.getRow(1).font = { bold: true, color: { argb: "FFFFFF" } };
      sheet.getRow(1).fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "2E75B6" },
      };
      sheet.getRow(1).alignment = { horizontal: "center" };

      // Summary Table Data
      for (const userId in branchUserStatus[branch]) {
        const status = branchUserStatus[branch][userId];
        const row = sheet.addRow({
          username: status.username,
          lead: status.lead ? "Yes" : "No",
          todo: status.todo ? "Yes" : "No",
        });

        row.getCell("lead").fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: status.lead ? "D9EAD3" : "F4CCCC" },
        };
        row.getCell("todo").fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: status.todo ? "D9EAD3" : "F4CCCC" },
        };
        row.alignment = { horizontal: "center" };
        totalRowsGenerated++;
      }

      sheet.addRow([]);
      sheet.addRow([]);

      // Section Header for Todos
      const sectionRow = sheet.addRow(["Todos Created in the Interval"]);
      sectionRow.font = { bold: true, size: 13, color: { argb: "1F4E79" } };

      const subHeaderRow = sheet.addRow([
        "Username",
        "Title",
        "Description",
        "Priority",
        "Assigned To",
      ]);
      subHeaderRow.font = { bold: true, color: { argb: "FFFFFF" } };
      subHeaderRow.fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "5B9BD5" },
      };
      subHeaderRow.alignment = { horizontal: "center" };

      // Todos Table Data
      for (const userId in branchUserStatus[branch]) {
        const userStatus = branchUserStatus[branch][userId];
        const todos = todosByUser[userId] || [];
        for (const todo of todos) {
          sheet.addRow([
            userStatus.username,
            todo.title,
            todo.description,
            todo.priority,
            todo.assigned_to_name || "Self",
          ]);
          totalTodosDetailed++;
        }
      }

      sheet.columns.forEach(column => {
        if (column.width < 15) column.width = 15;
      });
    }

    // Write file locally
    const outputFilename = path.join(__dirname, `test_leads_todos_${now.format("YYYY_MM_DD_HHmmss")}.xlsx`);
    await workbook.xlsx.writeFile(outputFilename);
    console.log(`\nSUCCESS: Generated Excel report successfully!`);
    console.log(`   File saved to: ${outputFilename}`);
    console.log(`   Branches: ${sortedBranches.length}`);
    console.log(`   Summary rows: ${totalRowsGenerated}`);
    console.log(`   Detailed todo rows: ${totalTodosDetailed}`);

    // Optional email sending
    if (sendEmail) {
      console.log(`\n5. Sending test email to ${targetEmail}...`);
      const nodemailer = require("nodemailer");
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: "crmmalabar@gmail.com",
          pass: "rhmo laoh qara qrnd",
        },
      });

      const buffer = fs.readFileSync(outputFilename);
      await transporter.sendMail({
        from: '"MTC Sync (Test)" <crmmalabar@gmail.com>',
        to: [targetEmail],
        subject: `[TEST] Daily Leads & Todo Report for ${now.format("DD-MM-YYYY")}`,
        html: `
          <h2>[TEST] Daily Leads & Todo Report</h2>
          <p><strong>Report Period:</strong> ${start.format("DD-MM-YYYY HH:mm")} to ${end.format("DD-MM-YYYY HH:mm")}</p>
          <p>This is a test run of the daily leads and todo report.</p>
        `,
        attachments: [{
          filename: `test_leads_todos_${now.format("YYYY_MM_DD")}.xlsx`,
          content: buffer,
          contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        }],
      });
      console.log(`   Email sent successfully to ${targetEmail}!`);
    }

    console.log("\n=== Test Completed Successfully ===");
    return { success: true, outputFilename };
  } catch (err) {
    console.error("\nTest Failed with Error:", err);
    throw err;
  }
}

// If executed directly from command line (e.g. `node testDailyReport.js`)
if (require.main === module) {
  const args = process.argv.slice(2);
  const shouldSendEmail = args.includes("--send-email");
  const targetEmail = args.find(a => a.startsWith("--to="))?.split("=")[1] || "performancemtc@gmail.com";

  testDailyTodoReport({ sendEmail: shouldSendEmail, targetEmail })
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
}

module.exports = { testDailyTodoReport };
