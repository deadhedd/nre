const fs = require('fs');
const path = require('path');

// === CONFIG ===
const sleepFolder = path.resolve(
  process.env.HOME,
  'automation/obsidian/vaults/Main/Sleep Data'
);
// Build today's date string in local YYYY-MM-DD
const today = new Date();
const year = today.getFullYear();
const month = String(today.getMonth() + 1).padStart(2, '0');
const day = String(today.getDate()).padStart(2, '0');
const dateToProcess = `${year}-${month}-${day}`;

const inputPath = path.join(sleepFolder, `${dateToProcess}.txt`);
const outputPath = path.join(sleepFolder, `${dateToProcess} Sleep Summary.md`);

// === UTILITIES ===
function toMinutes(durationStr) {
  const parts = durationStr.split(':').map(p => parseInt(p, 10));
  if (parts.length === 3)      return parts[0] * 60 + parts[1] + parts[2] / 60;
  else if (parts.length === 2) return parts[0]     + parts[1] / 60;
  else if (parts.length === 1) return parts[0] / 60;
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
  if (!m) return null;
  const [, mon, day, yr, hr, min, ampm] = m;
  const months = { Jan:0, Feb:1, Mar:2, Apr:3, May:4, Jun:5,
                   Jul:6, Aug:7, Sep:8, Oct:9, Nov:10, Dec:11 };
  let hour = parseInt(hr, 10), minute = parseInt(min, 10);
  if (ampm === 'PM' && hour !== 12) hour += 12;
  if (ampm === 'AM' && hour === 12) hour = 0;

  return new Date(
    parseInt(yr, 10),
    months[mon.slice(0,3)],
    parseInt(day, 10),
    hour,
    minute
  );
}

function formatLocalDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Process a single date's raw file and return totalMin excluding Awake
function processDate(dateStr) {
  const filePath = path.join(sleepFolder, `${dateStr}.txt`);
  if (!fs.existsSync(filePath)) return null;
  const raw = fs.readFileSync(filePath, 'utf8');
  const lines = raw.split('\n').map(l => l.trim()).filter(Boolean);
  const q = Math.floor(lines.length / 4);
  if (q * 4 !== lines.length) return null;
  const stages   = lines.slice(0, q);
  const durations= lines.slice(q, 2*q);
  const starts   = lines.slice(2*q, 3*q);

  // cutoff: noon previous local day
  const [y, m, d] = dateStr.split('-').map(Number);
  const cutoff = new Date(y, m - 1, d - 1, 12, 0, 0);

  let total = 0;
  for (let i = 0; i < q; i++) {
    const st = parseTime(starts[i]);
    if (!st || st < cutoff) continue;
    if (stages[i] !== 'Awake') {
      total += toMinutes(durations[i]);
    }
  }
  return total;
}

// === STEP 1: ensure input exists ===
if (!fs.existsSync(inputPath)) {
  console.error(`❌ No input file for ${dateToProcess}`);
  process.exit(1);
}

// === STEP 2: read and slice today’s data ===
const rawToday = fs.readFileSync(inputPath, 'utf8');
const linesToday = rawToday.split('\n').map(l => l.trim()).filter(Boolean);
const q = Math.floor(linesToday.length / 4);
if (q * 4 !== linesToday.length) {
  console.error(`⚠️ ${linesToday.length} lines not divisible by 4`);
  process.exit(1);
}
const stagesToday   = linesToday.slice(0, q);
const durationsToday= linesToday.slice(q, 2*q);
const startsToday   = linesToday.slice(2*q, 3*q);
const endsToday     = linesToday.slice(3*q);

// cutoff for today
const cutoffDate = new Date(year, month-1, day-1, 12, 0, 0);

// collect today's entries
const entriesToday = [];
for (let i = 0; i < q; i++) {
  const st = parseTime(startsToday[i]);
  if (!st || st < cutoffDate) continue;
  entriesToday.push({
    stage: stagesToday[i],
    durationMin: toMinutes(durationsToday[i]),
    start: startsToday[i],
    end: endsToday[i]
  });
}

// compute totalMin excluding Awake
const totalMin = entriesToday
  .filter(e => e.stage !== 'Awake')
  .reduce((s, e) => s + e.durationMin, 0);
const totalH = Math.floor(totalMin / 60);
const totalM = Math.round(totalMin % 60);

// compute 7-day running average from past 7 days including today
const pastTotals = [];
for (let offset = 6; offset >= 0; offset--) {
  const d = new Date(year, month-1, day);
  d.setDate(d.getDate() - offset);
  const ds = formatLocalDate(d);
  const t = processDate(ds);
  if (t != null) pastTotals.push(t);
}
const sum7 = pastTotals.reduce((s, t) => s + t, 0);
const avgMin = sum7 / pastTotals.length;
const avgH = Math.floor(avgMin / 60);
const avgM = Math.round(avgMin % 60);

// prepare prev/next wiki links
const prev = new Date(year, month-1, day);
prev.setDate(prev.getDate() - 1);
const prevKey = formatLocalDate(prev);
const next = new Date(year, month-1, day);
next.setDate(next.getDate() + 1);
const nextKey = formatLocalDate(next);
const links = [];
links.push(`[[${prevKey} Sleep Summary|← ${prevKey} Sleep Summary]]`);
links.push(`[[${nextKey} Sleep Summary|${nextKey} Sleep Summary →]]`);
const linkLine = links.join(' | ');

// breakdown by stage (including Awake)
const byStage = {};
entriesToday.forEach(e => {
  byStage[e.stage] = (byStage[e.stage] || 0) + e.durationMin;
});

// assemble markdown
let md = '';
md += linkLine + '\n\n';
md += `## Sleep Summary for ${dateToProcess}\n\n`;
md += `🛌 Total (excl. Awake): ${totalH}h ${totalM}m (` +
          `${totalMin.toFixed(2)} min)\n\n`;
md += `📈 7-day running average: ${avgH}h ${avgM}m (` +
          `${avgMin.toFixed(2)} min)\n\n`;
md += `### By Stage:\n`;
Object.entries(byStage).forEach(([stage, mins]) => {
  const sh = Math.floor(mins/60), sm = Math.round(mins%60);
  md += `- ${stage}: ${sh}h ${sm}m (${mins.toFixed(2)} min)\n`;
});
md += `\n---\n\n### Full Entries\n`;
entriesToday.forEach(e => {
  md += `- ${e.stage.padEnd(6)} | ${e.durationMin.toFixed(2)} min | ${e.start} → ${e.end}\n`;
});

// write file
fs.writeFileSync(outputPath, md);
console.log(`✅ Wrote ${path.basename(outputPath)}`);