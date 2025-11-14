const fs = require('fs');
const path = require('path');

// Helper to get ISO week number and year
function getCurrentWeekTag() {
  const now = new Date();
  const jan1 = new Date(now.getFullYear(), 0, 1);
  const days = Math.floor((now - jan1) / (24 * 60 * 60 * 1000));
  const week = Math.ceil((days + jan1.getDay() + 1) / 7);
  const isoWeek = String(week).padStart(2, '0');
  return `${now.getFullYear()}-W${isoWeek}`;
}

function getWeeklyGoalBlock() {
  const weekTag = getCurrentWeekTag();
  const vaultPath = '/home/obsidian/vaults/Main';
  const relativePath = `Periodic Notes/Weekly Notes/${weekTag}.md`;
  const fullPath = path.join(vaultPath, relativePath);

  if (!fs.existsSync(fullPath)) {
    return `❌ Could not find file: ${relativePath}`;
  }

  const contents = fs.readFileSync(fullPath, 'utf-8');
  const lines = contents.split('\n');

  const startHeading = '## 🎯 Weekly Goal';
  const startIndex = lines.findIndex(line => line.trim() === startHeading);

  if (startIndex === -1) {
    return `❌ Could not find heading '${startHeading}' in ${relativePath}`;
  }

  // Look for the next section header or end of file
  let endIndex = lines.length;
  for (let i = startIndex + 1; i < lines.length; i++) {
    if (lines[i].startsWith('## ')) {
      endIndex = i;
      break;
    }
  }

  const sectionLines = lines.slice(startIndex + 1, endIndex);
  const result = sectionLines.join('\n').trim();

  return result || '⚠️ Weekly Goal section is empty.';
}

module.exports = getWeeklyGoalBlock;