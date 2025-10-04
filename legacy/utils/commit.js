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
 * @param {{context?: string}} [options] - Optional logging context.
 */
module.exports = function commit(repoRoot, files, message, options = {}) {
  const context =
    typeof options === 'string'
      ? options
      : options && typeof options === 'object' && options.context
        ? options.context
        : 'changes';

  try {
    const arr = Array.isArray(files) ? files : [files];
    const relPaths = arr.map((f) => path.relative(repoRoot, f));
    const quoted = relPaths.map((p) => JSON.stringify(p)).join(' ');
    sh(`git -C ${JSON.stringify(repoRoot)} add -- ${quoted}`);
    try {
      sh(`git -C ${JSON.stringify(repoRoot)} commit -m ${JSON.stringify(message)}`);
    } catch (commitErr) {
      console.warn('⚠️ No changes to commit:', commitErr?.message || commitErr);
    }
  } catch (err) {
    const prefix = context === 'changes' ? '⚠️ Failed to commit changes:' : `⚠️ Failed to commit ${context}:`;
    console.error(prefix, err?.message || err);
  }
};
