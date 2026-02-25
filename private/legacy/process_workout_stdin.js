#!/usr/bin/env node
const fs   = require('fs');
const path = require('path');
const commit = require('./utils/commit');

(async()=>{
  // 1) read all of stdin
  let raw = '';
  for await(const chunk of process.stdin) raw += chunk;
  raw = raw.trim();
  if (!raw) {
    console.error('No data received.');
    process.exit(1);
  }

  // 2) paths
  const date = new Date().toISOString().split('T')[0]; // e.g. 2025-06-10
  const vaultRoot = path.join(process.env.HOME, 'automation/obsidian/vaults/Main');
  const rawDir    = path.join(vaultRoot, 'Workout Data');
  const outDir    = path.join(vaultRoot, 'Periodic Notes');

  for (let d of [rawDir, outDir]) {
    if (!fs.existsSync(d)) fs.mkdirSync(d, {recursive:true});
  }

  // 3) write raw file
  const rawPath = path.join(rawDir, `${date}.txt`);
  fs.writeFileSync(rawPath, raw + '\n');

  // 4) parse & build markdown
  const lines = raw.split('\n');
  let md = `## Workout — ${date}\n\n`;

  for (let i = 0; i < lines.length; ) {
    const entry = {};
    while (i < lines.length && lines[i].trim() !== '---') {
      let [key, ...rest] = lines[i].split(':');
      entry[key.trim()] = rest.join(':').trim();
      i++;
    }
    i++; // skip the '---'
    if (!entry.Type) continue;

    md += `- **${entry.Type}** (${entry.Duration})\n`;
    md += `  - Calories: ${entry.Calories}\n`;
    if (entry.Distance)  md += `  - Distance: ${entry.Distance}\n`;
    if (entry['Avg HR']) md += `  - Avg HR: ${entry['Avg HR']}\n`;
    md += `  - Time: ${entry.Start} – ${entry.End}\n\n`;
  }

  // 5) write markdown
  const outPath = path.join(outDir, `${date}-workout.md`);
  fs.writeFileSync(outPath, md);
  console.log('✅ Workout note generated:', outPath);

  // Commit raw and markdown workout files
  commit(vaultRoot, [rawPath, outPath], `workout: ${date}`);
})();
