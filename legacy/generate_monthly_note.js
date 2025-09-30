#!/usr/bin/env node
/**
 * generateMonthlyNote.js
 * Create a monthly note directly (no Templater). Safe, dependency‑free Node.
 *
 * Default behavior:
 *   - Writes to: /home/obsidian/vaults/Main/Periodic Notes/Monthly Notes/<YYYY-MM>.md (creates folder if missing)
 *   - Generates title: "# <Month Name> <YYYY>"
 *   - Adds prev/next month wiki links using YYYY-MM tags
 *   - Inserts a Dataview block that filters by due/<YYYY-MM>, due/<YYYY-QN>, and due/<YYYY>
 *
 * CLI options:
 *   --vault "<path>"        Root folder to write into (default: /home/obsidian/vaults/Main)
 *   --outdir "<name>"       Subfolder for monthly notes (default: Periodic Notes/Monthly Notes)
 *   --date "YYYY-MM"        Month to generate (default: current month in your timezone)
 *   --locale "en-US"        Month name locale (default: en-US)
 *   --force                 Overwrite if file exists (default: false)
 *
 * Examples:
 *   node generateMonthlyNote.js
 *   node generateMonthlyNote.js --vault "/path/to/vault" --date 2025-09
 *   node generateMonthlyNote.js --outdir "Periodic Notes/Monthly Notes" --force
 *
 * Author: deadhedd
 */

const fs = require("fs");
const path = require("path");

const DEFAULT_VAULT_PATH = "/home/obsidian/vaults/Main";
const DEFAULT_MONTHLY_NOTES_DIR = path.join(
  "Periodic Notes",
  "Monthly Notes"
);

/** Parse CLI args (simple, no deps) */
function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--force") {
      args.force = true;
    } else if (a.startsWith("--")) {
      const key = a.slice(2);
      const val = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
      args[key] = val;
    }
  }
  return args;
}

function ensureDir(p) {
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

/** Format helpers */
function pad2(n) { return String(n).padStart(2, "0"); }

function monthName(date, locale = "en-US") {
  return new Intl.DateTimeFormat(locale, { month: "long", timeZone: "UTC" }).format(date);
}

function toFirstOfMonthUTC(year, monthIndex0) {
  // monthIndex0 is 0..11
  const d = new Date(Date.UTC(year, monthIndex0, 1, 0, 0, 0));
  return d;
}

function shiftMonthUTC(dateUTC, delta) {
  return toFirstOfMonthUTC(dateUTC.getUTCFullYear(), dateUTC.getUTCMonth() + delta);
}

/** Derive tags for year, month, quarter */
function computePeriod(dateUTC) {
  const y = dateUTC.getUTCFullYear();
  const mIdx = dateUTC.getUTCMonth(); // 0..11
  const m = mIdx + 1; // 1..12
  const monthTag = `${y}-${pad2(m)}`;
  const q = Math.floor(mIdx / 3) + 1;
  const quarterTag = `${y}-Q${q}`;

  const prevUTC = shiftMonthUTC(dateUTC, -1);
  const nextUTC = shiftMonthUTC(dateUTC, +1);
  const prevTag = `${prevUTC.getUTCFullYear()}-${pad2(prevUTC.getUTCMonth() + 1)}`;
  const nextTag = `${nextUTC.getUTCFullYear()}-${pad2(nextUTC.getUTCMonth() + 1)}`;

  return {
    year: y,
    monthIndex0: mIdx,
    monthTag,
    quarterTag,
    prevTag,
    nextTag,
    titleMonthName: monthName(dateUTC),
  };
}

/** Build the note content */
function buildContent(p) {
  return `# ${p.titleMonthName} ${p.year}

- [[Periodic Notes/Monthly Notes/${p.prevTag}|${p.prevTag}]]
- [[Periodic Notes/Monthly Notes/${p.nextTag}|${p.nextTag}]]

## Cascading Tasks

\`\`\`dataview
task
from ""
where contains(tags, "due/${p.monthTag}")
   OR contains(tags, "due/${p.quarterTag}")
   OR contains(tags, "due/${p.year}")
\`\`\`

## Monthly Checklist

-  Check home maintenance tasks
-  Plan major goals for next month
- [ ] Clean out the fridge
- [ ] Order Johnie's inhaler
- [ ] Finance review

## budget

### Regular expenses:
##### Essentials:
- Garbage: 70 (Feb, May, Aug, Nov)
- Internet: 45 (Monthly)
- Electricity: 120-300 (Monthly)
- Car Payment: 616 (monthly)
- Car insurance 1750 (Jul, Nov)
**Total**: 781-2781
##### Non-essentials:
- Chatgpt: 22 (Monthly)
- YT Premium: 25 (Monthly)
- Audible 18 (Bi-monthly (odd))
- Patreon: 4 (Monthly)
- Apple Music: 11 (Monthly)
- Fitbod: 80 (Yearly (Oct))
- itunes match: 25 (Yearly (Jun))
- F1TV: 85 (Jul)
**Total**: 62-227

##### **Total Regular Expenses:
- 843-3008
##### Income:
(~1400 expected)
- (###)
##### Expenses:
- (###)
##### Net:
- (###)

## Goals

## Review

- What went well:

- What didn’t:

- Lessons learned:

## Notes
`;
}

function main() {
  const args = parseArgs(process.argv);
  const cwd = process.cwd();

  const vault = args.vault
    ? path.resolve(cwd, args.vault)
    : DEFAULT_VAULT_PATH;
  const outdir = args.outdir ? args.outdir : DEFAULT_MONTHLY_NOTES_DIR;
  const locale = args.locale ? args.locale : "en-US";
  const force = !!args.force;

  // Resolve target month
  let targetUTC;
  if (args.date) {
    const m = /^(\d{4})-(\d{2})$/.exec(String(args.date));
    if (!m) {
      console.error('Error: --date must be in format YYYY-MM (e.g., 2025-09)');
      process.exit(2);
    }
    const yr = Number(m[1]);
    const mi = Number(m[2]);
    if (mi < 1 || mi > 12) {
      console.error('Error: --date month must be 01..12');
      process.exit(2);
    }
    targetUTC = toFirstOfMonthUTC(yr, mi - 1);
  } else {
    const now = new Date();
    targetUTC = toFirstOfMonthUTC(now.getUTCFullYear(), now.getUTCMonth());
  }

  // Build values
  const p = computePeriod(targetUTC);
  // Override locale for month name if requested
  p.titleMonthName = monthName(targetUTC, locale);

  // Paths
  const dirPath = path.join(vault, outdir);
  const fileName = `${p.monthTag}.md`;
  const filePath = path.join(dirPath, fileName);

  ensureDir(dirPath);

  const content = buildContent(p);

  if (fs.existsSync(filePath) && !force) {
    console.error(`Refusing to overwrite existing file: ${filePath}
Use --force to overwrite.`);
    process.exit(1);
  }

  fs.writeFileSync(filePath, content, "utf8");

  console.log(`Monthly note written: ${filePath}`);
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error("Fatal error:", err && err.stack ? err.stack : err);
    process.exit(1);
  }
}
