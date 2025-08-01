const fs = require('fs');
const path = require('path');

module.exports = async () => {
  const today = new Date();
  const dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const todayName = dayNames[today.getDay()];
  const tomorrowName = dayNames[(today.getDay() + 1) % 7];

  // This path is specific to your vault layout — adjust if needed
  const vaultBase = '/home/chris/automation/obsidian/vaults/Main';
  const relativePath = "000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Templates/Daily Plan.md";
  const filePath = path.join(vaultBase, relativePath);

  const raw = await fs.promises.readFile(filePath, "utf-8");

  function extractDaySection(dayName) {
    const lines = raw.split(/\r?\n/);
    const startIndex = lines.findIndex(line => line.trim().startsWith(`## ${dayName}`));

    if (startIndex === -1) {
      return `❓ No section found for ${dayName}`;
    }

    let endIndex = lines.length;
    for (let i = startIndex + 1; i < lines.length; i++) {
      if (lines[i].trim().startsWith("## ")) {
        endIndex = i;
        break;
      }
    }

    const sectionLines = lines.slice(startIndex + 1, endIndex);
    return sectionLines.join("\n").trim();
  }

  let output = `# Daily Note - ${todayName} (${today.toLocaleDateString()})\n\n`;
  output += extractDaySection(todayName);

  const tomorrowSection = extractDaySection(tomorrowName)
    .split("\n")
    .map(line => `${line}`)
    .join("\n");

  output += `\n\n## Preview of Tomorrow: ${tomorrowName}\n${tomorrowSection}`;

  return output;
};