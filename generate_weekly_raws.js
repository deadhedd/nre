const fs = require('fs');
const path = require('path');

// === CONFIG ===
const sleepFolder = path.resolve(
  process.env.HOME,
  'automation/obsidian/vaults/Main/Sleep Data'
);
const backlogPath = path.join(sleepFolder, 'backfill-raw.txt');

// === UTILS ===
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
  let hour = parseInt(hr,10), minute = parseInt(min,10);
  if (ampm==='PM' && hour!==12) hour += 12;
  if (ampm==='AM' && hour===12) hour = 0;
  return new Date(parseInt(yr,10), months[mon.slice(0,3)], parseInt(day,10), hour, minute);
}

function getNoteDate(dt) {
  // same noon cutoff logic
  const cutoff = new Date(dt);
  cutoff.setHours(12,0,0,0);
  if (dt < cutoff) return dt;
  return new Date(dt.getTime() + 86400000);
}

function formatLocal(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth()+1).padStart(2,'0');
  const day = String(d.getDate()).padStart(2,'0');
  return `${y}-${m}-${day}`;
}

// === READ BACKLOG ===
if (!fs.existsSync(backlogPath)) {
  console.error(`❌ backlog file not found: ${backlogPath}`);
  process.exit(1);
}
const raw = fs.readFileSync(backlogPath, 'utf8');
const lines = raw.split('\n').map(l=>l.trim()).filter(Boolean);
const count = lines.length;
const quarter = Math.floor(count/4);
if (quarter*4 !== count) {
  console.error(`⚠️ unexpected line count: ${count}`);
  process.exit(1);
}
const stages   = lines.slice(0, quarter);
const durations= lines.slice(quarter, 2*quarter);
const starts   = lines.slice(2*quarter, 3*quarter);
const ends     = lines.slice(3*quarter);

// === GROUP ENTRIES ===
const groups = {};
for (let i=0; i<quarter; i++) {
  const ts = parseTime(starts[i]);
  if (!ts) continue;
  const noteDt = getNoteDate(ts);
  const key = formatLocal(noteDt);
  if (!groups[key]) groups[key] = { stages:[], durations:[], starts:[], ends:[] };
  groups[key].stages.push(stages[i]);
  groups[key].durations.push(durations[i]);
  groups[key].starts.push(starts[i]);
  groups[key].ends.push(ends[i]);
}

// === WRITE PAST 7 DAYS ===
const today = new Date();
const outputs = [];
for (let offset=0; offset<7; offset++) {
  const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
  const key = formatLocal(d);
  if (groups[key]) {
    const outPath = path.join(sleepFolder, `${key}.txt`);
    const { stages, durations, starts, ends } = groups[key];
    const content = [
      ...stages,
      ...durations,
      ...starts,
      ...ends
    ].join('\n') + '\n';
    fs.writeFileSync(outPath, content);
    outputs.push(outPath);
  }
}

console.log('✅ Generated the following raw files for the past 7 days:');
outputs.forEach(f => console.log('-', f));