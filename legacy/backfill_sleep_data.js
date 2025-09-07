const fs = require('fs');
const path = require('path');
const commit = require('./utils/commit');

// === CONFIG ===
const vaultRoot = path.resolve(
  process.env.HOME,
  'automation/obsidian/vaults/Main'
);
const sleepFolder = path.join(vaultRoot, 'Sleep Data');
const inputPath = path.join(sleepFolder, 'backfill-raw.txt');

// === HELPERS ===
function toMinutes(durationStr) {
  const parts = durationStr.split(':').map(p => parseInt(p, 10));
  if (parts.length === 3)      return parts[0]*60 + parts[1] + parts[2]/60;
  else if (parts.length === 2) return parts[0]   + parts[1]/60;
  else if (parts.length === 1) return parts[0]/60;
  return 0;
}

function parseTime(str) {
  const cleaned = str
    .replace(/\u202F/g, ' ')
    .replace(/\u00A0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  const m = cleaned.match(
    /^([A-Za-z]+) (\d{1,2}), (\d{4}) at (\d{1,2}):(\d{2}) (AM|PM)$/
  );
  if (!m) {
    console.warn(`⚠️ Could not parse timestamp: "${str}"`);
    return null;
  }
  const [, mon, day, yr, hr, min, ampm] = m;
  const months = { Jan:0, Feb:1, Mar:2, Apr:3, May:4, Jun:5,
                   Jul:6, Aug:7, Sep:8, Oct:9, Nov:10, Dec:11 };
  let hour = parseInt(hr,10), minute = parseInt(min,10);
  if (ampm==='PM' && hour!==12) hour += 12;
  if (ampm==='AM' && hour===12) hour = 0;

  return new Date(
    parseInt(yr,10),
    months[mon.slice(0,3)],
    parseInt(day,10),
    hour,
    minute
  );
}

function formatLocalDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth()+1).padStart(2,'0');
  const day = String(d.getDate()).padStart(2,'0');
  return `${y}-${m}-${day}`;
}

function getSleepNoteDate(startDate) {
  const cutoff = new Date(startDate.getTime());
  cutoff.setHours(12,0,0,0);
  if (startDate < cutoff) {
    return formatLocalDate(startDate);
  } else {
    const next = new Date(startDate.getTime() + 86400000);
    return formatLocalDate(next);
  }
}

// === 1) Read & split raw data into four equal parts ===
const raw = fs.readFileSync(inputPath,'utf8');
const lines = raw.split('\n').map(l => l.trim()).filter(Boolean);
const chunk = Math.floor(lines.length / 4);

if (chunk * 4 !== lines.length) {
  console.error(`⚠️ ${lines.length} lines isn’t divisible by 4.`);
  process.exit(1);
}

const stages   = lines.slice(0, chunk);
const durations= lines.slice(chunk, 2*chunk);
const starts   = lines.slice(2*chunk, 3*chunk);
const ends     = lines.slice(3*chunk);

// === 2) Group entries by their “sleep note date” ===
const buckets = {};
for (let i = 0; i < chunk; i++) {
  const ts = parseTime(starts[i]);
  if (!ts) continue;
  const key = getSleepNoteDate(ts);
  buckets[key] = buckets[key] || [];
  buckets[key].push({
    stage: stages[i],
    durationMin: toMinutes(durations[i]),
    start: starts[i],
    end: ends[i]
  });
}

// === 3) Prepare sorted dates and totals (excluding Awake) ===
const sortedDates = Object.keys(buckets).sort();
const totalsMap = {};
for (const dateKey of sortedDates) {
  totalsMap[dateKey] = buckets[dateKey]
    .filter(e => e.stage !== 'Awake')
    .reduce((s,e) => s + e.durationMin, 0);
}

// === 4) Emit a summary file for each date ===
for (let i = 0; i < sortedDates.length; i++) {
  const dateKey = sortedDates[i];
  const entries = buckets[dateKey];
  const totalMin = totalsMap[dateKey];
  const totalH = Math.floor(totalMin / 60),
        totalM = Math.round(totalMin % 60);

  // 7-day running average
  const windowStart = Math.max(0, i - 6);
  const windowDates = sortedDates.slice(windowStart, i + 1);
  const windowSum = windowDates.reduce((s, d) => s + totalsMap[d], 0);
  const windowLen = windowDates.length;
  const avgMin = windowSum / windowLen;
  const avgH = Math.floor(avgMin / 60),
        avgM = Math.round(avgMin % 60);

  // build Obsidian wiki links
  const links = [];
  if (i > 0) {
    const prev = sortedDates[i-1];
    links.push(`[[${prev} Sleep Summary|← ${prev} Sleep Summary]]`);
  }
  if (i < sortedDates.length - 1) {
    const next = sortedDates[i+1];
    links.push(`[[${next} Sleep Summary|${next} Sleep Summary →]]`);
  }
  const linkLine = links.join(' | ');

  // breakdown by stage
  const byStage = {};
  for (const e of entries) {
    byStage[e.stage] = (byStage[e.stage] || 0) + e.durationMin;
  }

  // assemble markdown
  let md = '';
  if (linkLine) md += linkLine + '\n\n';
  md += `## Sleep Summary for ${dateKey}\n\n`;
  md += `🛌 Total (excl. Awake): ${totalH}h ${totalM}m (${totalMin.toFixed(2)} min)\n\n`;
  md += `📈 7-day running average: ${avgH}h ${avgM}m (${avgMin.toFixed(2)} min)\n\n`;
  md += `### By Stage:\n`;
  for (const [stage, mins] of Object.entries(byStage)) {
    const h = Math.floor(mins / 60), m = Math.round(mins % 60);
    md += `- ${stage}: ${h}h ${m}m (${mins.toFixed(2)} min)\n`;
  }
  md += `\n---\n\n### Full Entries\n`;
  for (const e of entries) {
    md += `- ${e.stage.padEnd(6)} | ${e.durationMin.toFixed(2)} min | ${e.start} → ${e.end}\n`;
  }

  const outPath = path.join(sleepFolder, `${dateKey} Sleep Summary.md`);
  fs.writeFileSync(outPath, md);
  console.log(`✅ Wrote: ${path.basename(outPath)}`);

  // Commit each generated sleep summary
  commit(vaultRoot, outPath, `sleep summary: ${dateKey}`);
}
