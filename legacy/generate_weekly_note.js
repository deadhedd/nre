#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const vaultPath = "/home/obsidian/vaults/Main";
const weeklyNotesDir = path.join(
  vaultPath,
  "Periodic Notes",
  "Weekly Notes"
);

const today = new Date();
const currentWeekTag = getISOWeek(today);
const prevWeekTag = getISOWeek(shiftDate(today, -7));
const nextWeekTag = getISOWeek(shiftDate(today, 7));
const currentMonthTag = getMonthTag(today);
const currentQuarterTag = getQuarterTag(today);
const currentYear = String(today.getFullYear());

const outputPath = path.join(weeklyNotesDir, `${currentWeekTag}.md`);

const noteLines = [
  `# Week ${currentWeekTag}`,
  "",
  `<<[[Periodic Notes/Weekly Notes/${prevWeekTag}|${prevWeekTag}]] || [[Periodic Notes/Weekly Notes/${nextWeekTag}|${nextWeekTag}]]>>`,
  "",
  "## 🎯 Weekly Goal",
  "",
  "**Goal:**  ",
  "`weekly_goal:: `",
  "",
  "**Why it matters:**  ",
  "> One or two sentences at most.",
  "",
  "**Definition of Done:**  ",
  "- [ ] Clear outcome  ",
  "- [ ] Observable result  ",
  "",
  "---",
  "",
  "## 📋 Weekly Checklist",
  "(These need to be incorporated into the cascading tasks system)",
  "- [ ] Weekly Review",
  "- [ ] Plan Weekly Goal",
  "- [ ] Review Calendar",
  "- [ ] Prep Meals / Ingredients",
  "",
  "---",
  "",
  "## 🧩 Cascading Tasks",
  "",
  "```dataview",
  "task",
  'from ""',
  `where contains(tags, "due/${currentWeekTag}")`,
  `   OR contains(tags, "due/${currentMonthTag}")`,
  `   OR contains(tags, "due/${currentQuarterTag}")`,
  `   OR contains(tags, "due/${currentYear}")`,
  "```",
  "",
  "## Links",
  "",
  "[[Weekly Routine]]",
  "[[Weekly Goal Queue]]",
  "[[Weekly Note Template]]",
  "",
];

const noteContent = noteLines.join("\n");

try {
  fs.mkdirSync(weeklyNotesDir, { recursive: true });
  fs.writeFileSync(outputPath, noteContent);
  console.log(`✅ Weekly note created: ${outputPath}`);
} catch (err) {
  console.error("❌ Error generating weekly note:", err.message);
  process.exit(1);
}

function shiftDate(date, days) {
  const copy = new Date(date.getTime());
  copy.setDate(copy.getDate() + days);
  return copy;
}

function getISOWeek(date) {
  const tempDate = new Date(
    Date.UTC(date.getFullYear(), date.getMonth(), date.getDate())
  );
  const dayNumber = tempDate.getUTCDay() || 7;
  tempDate.setUTCDate(tempDate.getUTCDate() + 4 - dayNumber);
  const yearStart = new Date(Date.UTC(tempDate.getUTCFullYear(), 0, 1));
  const weekNumber = Math.ceil(((tempDate - yearStart) / 86400000 + 1) / 7);
  const isoYear = tempDate.getUTCFullYear();
  return `${isoYear}-W${String(weekNumber).padStart(2, "0")}`;
}

function getMonthTag(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

function getQuarterTag(date) {
  const year = date.getFullYear();
  const quarter = Math.floor(date.getMonth() / 3) + 1;
  return `Q${quarter}-${year}`;
}
