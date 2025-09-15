const fs = require("fs");
const path = require("path");

// 🛠️ Set your paths
const templatePath = "C:/Users/Chris/Documents/Obsidian Vault/000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Templates/Weekly Note Template.md";
const outputDir = "C:/Users/Chris/Documents/Obsidian Vault/000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Weekly Notes";

// 📅 Get today's ISO week
const today = new Date();
const isoWeek = getISOWeek(today);
const outputPath = path.join(outputDir, `${isoWeek}.md`);

// ✅ Read template and inject values
try {
  const template = fs.readFileSync(templatePath, "utf-8");

  const rendered = template
    .replace(/<% tp\.date\.now\("YYYY-\[W\]WW"\) %>/g, isoWeek)
    .replace(/<% tp\.date\.now\("YYYY-MM-DD"\) %>/g, getDate(today));

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  fs.writeFileSync(outputPath, rendered);
  console.log(`✅ Weekly note created: ${outputPath}`);
} catch (err) {
  console.error("❌ Error generating weekly note:", err.message);
}

// === Helpers ===
function getISOWeek(d) {
  const target = new Date(d.valueOf());
  const dayNr = (d.getDay() + 6) % 7;
  target.setDate(target.getDate() - dayNr + 3);
  const firstThursday = target.valueOf();
  target.setMonth(0, 1);
  if (target.getDay() !== 4) {
    target.setMonth(0, 1 + ((4 - target.getDay()) + 7) % 7);
  }
  const week = 1 + Math.ceil((firstThursday - target) / 604800000);
  return `${d.getFullYear()}-W${String(week).padStart(2, "0")}`;
}

function getDate(d) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}
