#!/usr/bin/env node
/**
 * generateYearlyNote.js
 * Create a yearly note directly (no Templater). Dependency-free Node.
 *
 * Default behavior:
 *   - Writes to: /home/obsidian/vaults/Main/Periodic Notes/Yearly Notes/<YYYY>.md (creates folder if missing)
 *   - Title: "# <YYYY>"
 *   - Prev/Next links: [[YYYY-1]] and [[YYYY+1]]
 *   - Dataview task filter for due/<YYYY>
 *
 * CLI options:
 *   --vault "<path>"   Root folder to write into (default: /home/obsidian/vaults/Main)
 *   --outdir "<name>"  Subfolder for yearly notes (default: Periodic Notes/Yearly Notes)
 *   --year "YYYY"      Year to generate (default: current UTC year)
 *   --force            Overwrite if file exists
 *
 * Examples:
 *   node generateYearlyNote.js
 *   node generateYearlyNote.js --vault "/path/to/vaults/Main" --year 2026
 *   node generateYearlyNote.js --outdir "Periodic Notes/Yearly Notes" --force
 *
 * Author: deadhedd
 */

const fs = require("fs");
const path = require("path");

const DEFAULT_VAULT_PATH = "/home/obsidian/vaults/Main";
const DEFAULT_YEARLY_NOTES_DIR = path.join(
  "Periodic Notes",
  "Yearly Notes"
);

/* ---------------- CLI helpers ---------------- */
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

/* ---------------- Content builder ---------------- */
function buildContent(year) {
  const prevYear = year - 1;
  const nextYear = year + 1;

  return `# ${year}

- [[${prevYear}]]
- [[${nextYear}]]

## Cascading Tasks

\`\`\`dataview
task
from ""
where contains(tags, "due/${year}")
\`\`\`

## Yearly Checklist

-  Reflect on the past year
-  Set yearly theme or focus
-  Define major life goals
-  Create financial plan
-  Plan vacations / time off
-  Assess personal habits and routines
-  Declutter home, digital spaces, and commitments

## Annual Theme / Focus

## Major Goals

## Review

- Highlights of the year:

- Challenges faced:

- Lessons learned:

- Changes for next year:

## Notes
`;
}

/* ---------------- Main ---------------- */
function main() {
  const args = parseArgs(process.argv);
  const cwd = process.cwd();

  const vault = args.vault
    ? path.resolve(cwd, args.vault)
    : DEFAULT_VAULT_PATH;
  const outdir = args.outdir ? args.outdir : DEFAULT_YEARLY_NOTES_DIR;
  const force = !!args.force;

  // Determine target year
  let year;
  if (args.year) {
    const m = /^(\d{4})$/.exec(String(args.year));
    if (!m) {
      console.error('Error: --year must be "YYYY" (e.g., 2025).');
      process.exit(2);
    }
    year = Number(m[1]);
  } else {
    const now = new Date();
    year = now.getUTCFullYear();
  }

  const dirPath = path.join(vault, outdir);
  const fileName = `${year}.md`;
  const filePath = path.join(dirPath, fileName);

  ensureDir(dirPath);

  const content = buildContent(year);

  if (fs.existsSync(filePath) && !force) {
    console.error(`Refusing to overwrite existing file: ${filePath}
Use --force to overwrite.`);
    process.exit(1);
  }

  fs.writeFileSync(filePath, content, "utf8");
  console.log(`Yearly note written: ${filePath}`);
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error("Fatal error:", err && err.stack ? err.stack : err);
    process.exit(1);
  }
}
