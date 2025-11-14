const fs = require('fs');
const path = require('path');

function getTaggedChecklist() {
  const vaultPath = '/home/obsidian/vaults/Main';
  const filePath = path.join(vaultPath, 'Inbox/Combined Task List.md');

  if (!fs.existsSync(filePath)) {
    return '❌ Could not find Inbox/Combined Task List.md';
  }

  const contents = fs.readFileSync(filePath, 'utf-8');
  const lines = contents.split('\n');

  const grouped = {};

  for (const line of lines) {
    if (!line.trim().startsWith('- [ ]')) continue;

    const tags = line.match(/#[\w/-]+/g);
    if (!tags) continue;

    for (const tag of tags) {
      if (!grouped[tag]) grouped[tag] = [];

      const cleaned = line.replace(/\s*#[\w/-]+/g, '').trim();
      grouped[tag].push(cleaned);
    }
  }

  const sortedTags = Object.keys(grouped).sort();

  const formatTagHeading = (tag) => {
    return tag.slice(1).split(/[-_]/)
      .map(w => w.charAt(0).toUpperCase() + w.slice(1))
      .join(' ') + ' List';
  };

  let output = '';
  for (const tag of sortedTags) {
    const heading = formatTagHeading(tag);
    output += `#### ${heading}\n`;
    for (const item of grouped[tag]) {
      output += `${item}\n`;
    }
    output += '\n';
  }

  return output.trim();
}

module.exports = getTaggedChecklist;