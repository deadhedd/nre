const fs = require("fs");
const path = require("path");
const commit = require("./utils/commit");

// Load helper modules
const dayPlan = require("./utils/day_plan");
const f1Schedule = require("./utils/f1_schedule");
const getWeeklyGoal = require("./utils/get_weekly_goal_block");


(async () => {
  try {
    const vaultPath = "/home/obsidian/vaults/Main";
    const dailyNoteDir = path.join(
      vaultPath,
      "Periodic Notes",
      "Daily Notes"
    );

    const today = new Date();
    const year = today.getFullYear();
    const month = String(today.getMonth() + 1).padStart(2, "0");
    const day = String(today.getDate()).padStart(2, "0");
    const dateStr = `${year}-${month}-${day}`;
    const fileName = `${dateStr}.md`;
    const filePath = path.join(dailyNoteDir, fileName);

    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);
    const tomorrow = new Date(today);
    tomorrow.setDate(today.getDate() + 1);
    const formatDate = (date) =>
      `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;

    // Generate dynamic sections
    const dayPlanText = await dayPlan();
    const f1Text = await f1Schedule();
    const weeklyGoalText = await getWeeklyGoal();

    // Compose note content
    const content = `---
tags:
  - matter/daily-notes
---
<< [[${formatDate(yesterday)}]] | [[${formatDate(tomorrow)}]] >>

${dayPlanText}

## 🌤️ Yard Work Suitability
<!-- yard-work-check -->

---
${f1Text}

---
# Themes and Goals

## [[Yearly theme]] (2025)
The year of standing on business  
[[Stand on Business List]]

## [[Season Theme]] (2025 Spring)
Yard work and home repairs  

## 🎯 Weekly Goal
${weeklyGoalText}

---

# ☑️ Pending Tasks
### Stand on Business
\`\`\`tasks
not done
tags include #stand-on-business
\`\`\`

### Comms Queue
\`\`\`tasks
not done
tags include #comms-queue 
\`\`\`

### Device Config
\`\`\`tasks
not done
tags include #device-config
\`\`\`

### Quick Wins
\`\`\`tasks
not done
tags include #quick-wins
\`\`\`

### Someday/Maybe
\`\`\`tasks
not done
tags include #someday-maybe
\`\`\`

---

# Periodic Notes

[[${dateStr.slice(0, 4)}-W${String(getWeekNumber(today)).padStart(2, "0")}|This Week]]  
[[${today.toLocaleString("default", { month: "long" })} ${year}|This Month]]  
[[${year}-Q${Math.ceil((today.getMonth() + 1) / 3)}|This Quarter]]  
[[${year}|This Year]]

---

# Links  
[[Weekly Routine]]  
[[Consider Johnie]]  
[[Daily Note Template]]  
[[Daily Plan]]  
[[Workout Schedule]]
`;

    // Ensure directory exists
    if (!fs.existsSync(dailyNoteDir)) {
      throw new Error(`❌ Daily notes folder does not exist: ${dailyNoteDir}`);
    }

    // Write to file (overwrite if it exists; change to {flag:'wx'} to prevent overwrite)
    fs.writeFileSync(filePath, content);
    console.log(`✅ Daily note created at ${filePath}`);

    // --- Commit only (post-commit hook will auto-push) ---
    commit(vaultPath, filePath, `daily note: ${dateStr}`);
  } catch (err) {
    console.error("❌ Error creating daily note:", err);
  }

  function getWeekNumber(date) {
    const firstDay = new Date(date.getFullYear(), 0, 1);
    const dayOfYear = Math.floor((date - firstDay) / 86400000) + 1;
    return Math.ceil((dayOfYear + firstDay.getDay()) / 7);
  }
})();
