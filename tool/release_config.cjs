const { execFileSync } = require('node:child_process');
const { appendFileSync } = require('node:fs');

function releaseConfig(env, resolveTag) {
  const tagPush = env.GITHUB_EVENT_NAME === 'push' && env.GITHUB_REF?.startsWith('refs/tags/v');
  const manual = env.GITHUB_EVENT_NAME === 'workflow_dispatch' && env.PUBLISH_RELEASE === 'true';
  const publish = Boolean(tagPush || manual);
  const tag = tagPush ? env.GITHUB_REF_NAME : (env.RELEASE_TAG || '').trim();
  if (publish) {
    if (!/^v\d+(?:\.\d+){1,2}(?:-(?:alpha|beta|rc)(?:[.-]?\d+)?)?$/.test(tag)) {
      throw new Error('Publishing requires a version tag, for example v0.04-beta or v1.2.3.');
    }
    const existing = resolveTag(tag);
    if (existing && existing !== env.GITHUB_SHA) {
      throw new Error(`Tag ${tag} points to another commit; select that tag or use a new version.`);
    }
  }
  const label = publish ? tag : env.GITHUB_REF_NAME.replace(/[^a-zA-Z0-9._-]/g, '-');
  return { publish: String(publish), tag: publish ? tag : '', label };
}

if (require.main === module) {
  const config = releaseConfig(process.env, (tag) => {
    try {
      return execFileSync('git', ['rev-parse', '--verify', `refs/tags/${tag}^{commit}`], {
        encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
    } catch { return null; }
  });
  appendFileSync(process.env.GITHUB_OUTPUT,
    Object.entries(config).map(([key, value]) => `${key}=${value}\n`).join(''));
  console.log(`Build label: ${config.label}; publish release: ${config.publish}`);
}

module.exports = { releaseConfig };
