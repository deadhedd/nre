const path = require('path');
const { execSync } = require('node:child_process');

function sh(cmd) {
  execSync(cmd, { stdio: 'inherit' });
}

/**
 * Stage and commit file(s) to the git repository.
 * @param {string} repoRoot - Root directory of the git repository.
 * @param {string|string[]} files - Absolute path or array of paths to commit.
 * @param {string} message - Commit message.
 */
module.exports = function commit(repoRoot, files, message) {
  try {
    const arr = Array.isArray(files) ? files : [files];
    const relPaths = arr.map((f) => path.relative(repoRoot, f));
    const quoted = relPaths.map((p) => JSON.stringify(p)).join(' ');
    sh(`git -C ${JSON.stringify(repoRoot)} add -- ${quoted}`);
    try {
      sh(`git -C ${JSON.stringify(repoRoot)} commit -m ${JSON.stringify(message)}`);
    } catch (_) {
      // no-op if there were no changes
    }
  } catch (e) {
    console.error('⚠️ Commit step failed:', e?.message || e);
  }
};
