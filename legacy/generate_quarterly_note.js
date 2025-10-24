#!/usr/bin/env node
/**
 * generateQuarterlyNote.js
 * Create a quarterly note directly (no Templater). Dependency-free Node.
 *
 * Default behavior:
 *   - Writes to: /home/obsidian/vaults/Main/Periodic Notes/Quarterly Notes/<YYYY-QN>.md (creates folder if missing)
 *   - Title: "# <YYYY-QN>" (e.g., "# 2025-Q3")
 *   - Prev/Next links use "Qn YYYY" format (e.g., [[Q2 2025]])
 *   - Dataview task filter for due/<YYYY-QN> and due/<YYYY>
 *
 * CLI options:
 *   --vault "<path>"        Root folder to write into (default: /home/obsidian/vaults/Main)
 *   --outdir "<name>"       Subfolder for quarterly notes (default: Periodic Notes/Quarterly Notes)
 *   --date "YYYY-QN"        Quarter to generate (e.g., 2025-Q3). If omitted, uses current quarter.
 *   --force                 Overwrite if file exists (default: false)
 *
 * Examples:
 *   node generateQuarterlyNote.js
 *   node generateQuarterlyNote.js --vault "/path/to/vaults/Main" --date 2025-Q3
 *   node generateQuarterlyNote.js --outdir "Periodic Notes/Quarterly Notes" --force
 *
 * Author: deadhedd
 */

const fs = require("fs");
const path = require("path");

const DEFAULT_VAULT_PATH = "/home/obsidian/vaults/Main";
const DEFAULT_QUARTERLY_NOTES_DIR = "Periodic Notes/Quarterly Notes";

/** ---------------- CLI + FS helpers ---------------- */
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

function pad2(n) { return String(n).padStart(2, "0"); }

/** ---------------- Quarter math ---------------- */
function getQuarterFromMonthIndex0(mIdx) {
  // mIdx: 0..11 -> 1..4
  return Math.floor(mIdx / 3) + 1;
}

function currentQuarterUTC() {
  const now = new Date();
  const y = now.getUTCFullYear();
  const q = getQuarterFromMonthIndex0(now.getUTCMonth());
  return { year: y, quarter: q };
}

function parseQuarterArg(qstr) {
  // Accept "YYYY-QN" where N is 1..4
  const m = /^(\d{4})-Q([1-4])$/.exec(String(qstr));
  if (!m) return null;
  return { year: Number(m[1]), quarter: Number(m[2]) };
}

function prevQuarter(year, q) {
  if (q === 1) return { year: year - 1, quarter: 4 };
  return { year, quarter: q - 1 };
}

function nextQuarter(year, q) {
  if (q === 4) return { year: year + 1, quarter: 1 };
  return { year, quarter: q + 1 };
}

/** ---------------- Content builder ---------------- */
function quarterTag(year, q) {
  return `${year}-Q${q}`;
}

function buildContent({ year, quarter }) {
  const tag = quarterTag(year, quarter);

  const { year: prevY, quarter: prevQ } = prevQuarter(year, quarter);
  const { year: nextY, quarter: nextQ } = nextQuarter(year, quarter);

  // Link text format required: "Qn YYYY"
  const prevLink = `Q${prevQ} ${prevY}`;
  const nextLink = `Q${nextQ} ${nextY}`;
  const prevTag = quarterTag(prevY, prevQ);
  const nextTag = quarterTag(nextY, nextQ);

  return `# ${tag}

- [[Periodic Notes/Quarterly Notes/${prevTag}|${prevLink}]]
- [[Periodic Notes/Quarterly Notes/${nextTag}|${nextLink}]]

## Cascading Tasks

\`\`\`dataview
task
from ""
where contains(tags, "due/${tag}")
   OR contains(tags, "due/${year}")
\`\`\`

## Quarterly Checklist

-  Review yearly goals
-  Set quarterly priorities
-  Review financial plan
-  Plan major home or work projects
-  Schedule any needed health checkups
-  Clean out unnecessary files or papers

## Major Goals

## Key Projects

## Review

- What went well:

- What didn’t:

- Lessons learned:

## Notes
`;
}

/** ---------------- Main ---------------- */
function main() {
  const args = parseArgs(process.argv);
  const cwd = process.cwd();

  const vault = args.vault
    ? path.resolve(cwd, args.vault)
    : DEFAULT_VAULT_PATH;
  const outdir = args.outdir ? args.outdir : DEFAULT_QUARTERLY_NOTES_DIR;
  const force = !!args.force;

  // Determine target quarter
  let target = null;
  if (args.date) {
    target = parseQuarterArg(args.date);
    if (!target) {
      console.error('Error: --date must be in format YYYY-QN, e.g., "2025-Q3".');
      process.exit(2);
    }
  } else {
    target = currentQuarterUTC();
  }

  const dirPath = path.join(vault, outdir);
  const fileName = `${quarterTag(target.year, target.quarter)}.md`;
  const filePath = path.join(dirPath, fileName);

  ensureDir(dirPath);

  const content = buildContent(target);

  if (fs.existsSync(filePath) && !force) {
    console.error(`Refusing to overwrite existing file: ${filePath}
Use --force to overwrite.`);
    process.exit(1);
  }

  fs.writeFileSync(filePath, content, "utf8");
  console.log(`Quarterly note written: ${filePath}`);
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error("Fatal error:", err && err.stack ? err.stack : err);
    process.exit(1);
  }
}
