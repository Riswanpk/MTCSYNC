const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const moment = require("moment-timezone");
const ExcelJS = require("exceljs");

// Only initialize if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

exports.sendDailyTodoReport = onSchedule(
  {
    schedule: "1 12 * * *",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
  },

  async (event) => {
    const now = moment().tz("Asia/Kolkata");
    const yesterday = now.clone().subtract(1, "day");

    // Do not send report on Sunday (isoWeekday 7)
    if (now.isoWeekday() === 7) {
      console.log("No report sent on Sunday.");
      return null;
    }

    let start, end;

    if (now.isoWeekday() === 1) { // Monday
      // Saturday 12:00 PM to Monday 12:00 PM
      const saturday = now.clone().subtract(2, "days");
      start = saturday.clone().hour(12).minute(0).second(0).millisecond(0);
      end = now.clone().hour(12).minute(0).second(0).millisecond(0);
    } else {
      // Previous day 12:00 PM to today 12:00 PM
      start = yesterday.clone().hour(12).minute(0).second(0).millisecond(0);
      end = now.clone().hour(12).minute(0).second(0).millisecond(0);
    }

    console.log(`Generating Daily Todo Report for interval: ${start.format()} to ${end.format()}`);

    try {
      // Fetch users
      const usersSnap = await admin.firestore().collection("users").get();
      const userMap = {};
      usersSnap.forEach(doc => {
        userMap[doc.id] = { ...doc.data(), uid: doc.id };
      });


      // Prepare user status per branch (only todo)
      const branchUserStatus = {};
      for (const userId in userMap) {
        const user = userMap[userId];
        const branch = user.branch || "Unknown";
        if (!branchUserStatus[branch]) branchUserStatus[branch] = {};
        branchUserStatus[branch][userId] = {
          todo: false,
          username: user.username || user.email || "Unknown"
        };
      }

      // Fetch all daily_report entries in the time window at once for efficiency
      const dailyReportSnap = await admin.firestore()
        .collection("daily_report")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(start.toDate()))
        .where("timestamp", "<", admin.firestore.Timestamp.fromDate(end.toDate()))
        .get();

      // Process daily_report entries (only todo)
      dailyReportSnap.forEach(doc => {
        const data = doc.data();
        let userId = data.userId || data.user_id || data.created_by;
        const type = data.type;

        // Fallback to match by email if userId is missing or not in userMap
        if ((!userId || !userMap[userId]) && data.email) {
          const targetEmail = data.email.trim().toLowerCase();
          for (const uid in userMap) {
            if (userMap[uid].email && userMap[uid].email.trim().toLowerCase() === targetEmail) {
              userId = uid;
              break;
            }
          }
        }

        if (userId && userMap[userId]) {
          const branch = userMap[userId].branch || "Unknown";
          if (branchUserStatus[branch] && branchUserStatus[branch][userId]) {
            if (type === "todo") {
              branchUserStatus[branch][userId].todo = true;
            }
          }
        }
      });

      // Fetch todos created/updated by each user in the interval
      // Query by created_by (userId) to match Flutter logic
      const todosByUser = {};
      
      // Get all todos in the time window
      const todosSnap = await admin.firestore()
        .collection("todo")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(start.toDate()))
        .where("timestamp", "<", admin.firestore.Timestamp.fromDate(end.toDate()))
        .get();

      // Group todos by user (using created_by or email)
      todosSnap.forEach(doc => {
        const data = doc.data();
        // Use created_by (userId) if available, otherwise find user by email
        let userId = data.created_by || data.userId;
        
        // If userId is missing or not in userMap, match by email
        if ((!userId || !userMap[userId]) && data.email) {
          const targetEmail = data.email.trim().toLowerCase();
          for (const uid in userMap) {
            if (userMap[uid].email && userMap[uid].email.trim().toLowerCase() === targetEmail) {
              userId = uid;
              break;
            }
          }
        }

        if (userId && userMap[userId]) {
          if (!todosByUser[userId]) {
            todosByUser[userId] = [];
          }
          todosByUser[userId].push({
            title: data.title || "",
            description: data.description || "",
            priority: data.priority || "High",
            status: data.status || "pending",
            assigned_to_name: data.assigned_to_name || null,
            assigned_by_name: data.assigned_by_name || null,
          });
        }
      });

      // Synchronize summary: If a user has any actual todos created in this interval,
      // mark their todo status as 'Yes' (true) in the summary table
      for (const userId in todosByUser) {
        if (todosByUser[userId] && todosByUser[userId].length > 0 && userMap[userId]) {
          const branch = userMap[userId].branch || "Unknown";
          if (branchUserStatus[branch] && branchUserStatus[branch][userId]) {
            branchUserStatus[branch][userId].todo = true;
          }
        }
      }

      // Generate Excel
      const workbook = new ExcelJS.Workbook();
      workbook.creator = "MTC Sync";
      workbook.created = new Date();

      const sortedBranches = Object.keys(branchUserStatus).sort();
      for (const branch of sortedBranches) {
        const sheet = workbook.addWorksheet(branch.substring(0, 31)); // Excel sheet name limit

        // Style header
        sheet.columns = [
          { header: "Username", key: "username", width: 25 },
          { header: "Todo", key: "todo", width: 12 },
        ];

        // Style header row
        sheet.getRow(1).font = { bold: true };
        sheet.getRow(1).fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: "FF005BAC" },
        };
        sheet.getRow(1).font = { bold: true, color: { argb: "FFFFFFFF" } };

        // Summary table data
        for (const userId in branchUserStatus[branch]) {
          const userStatus = branchUserStatus[branch][userId];
          const row = sheet.addRow({
            username: userStatus.username,
            todo: userStatus.todo ? "Yes" : "No",
          });

          // Color code Yes/No
          const todoCell = row.getCell(2);
          if (userStatus.todo) {
            todoCell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF90EE90" } };
          } else {
            todoCell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFCCCB" } };
          }
        }

        // Blank rows
        sheet.addRow([]);
        sheet.addRow([]);

        // Todos Table Header
        const todosHeaderRow = sheet.addRow(["Username", "Title", "Description", "Priority", "Assigned To"]);
        todosHeaderRow.font = { bold: true };
        todosHeaderRow.fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: "FF8CC63F" },
        };

        // Todos Table Data
        for (const userId in branchUserStatus[branch]) {
          const user = userMap[userId];
          const todos = todosByUser[userId] || [];
          for (const todo of todos) {
            sheet.addRow([
              user.username || user.email || "",
              todo.title,
              todo.description,
              todo.priority,
              todo.assigned_to_name || "Self",
            ]);
          }
        }

        // Auto-fit columns
        sheet.columns.forEach(column => {
          if (column.width < 15) column.width = 15;
        });
      }

      // Write Excel to buffer
      const buffer = await workbook.xlsx.writeBuffer();

      // Send email with Excel attachment
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: "crmmalabar@gmail.com",
          pass: "rhmo laoh qara qrnd", // Use Gmail App Password
        },
      });

      await transporter.sendMail({
        from: '"MTC Sync" <crmmalabar@gmail.com>',
        to: ["performancemtc@gmail.com"],
        subject: `Daily Todo Report for ${now.format("DD-MM-YYYY")}`,
        html: `
          <h2>Daily Todo Report</h2>
          <p><strong>Report Period:</strong> ${start.format("DD-MM-YYYY HH:mm")} to ${end.format("DD-MM-YYYY HH:mm")}</p>
          <p>Please find attached the daily todo report.</p>
          <br/>
          <p style="color: #666; font-size: 12px;">This report was automatically generated by MTC Sync.</p>
        `,
        attachments: [{
          filename: `leads_todos_${now.format("YYYY_MM_DD")}.xlsx`,
          content: buffer,
          contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        }],
      });

      console.log("Excel report sent successfully for interval:", start.format(), "to", end.format());
      return null;
    } catch (error) {
      console.error("Error generating Daily Todo Report:", error);
      throw error;
    }
  }
);
