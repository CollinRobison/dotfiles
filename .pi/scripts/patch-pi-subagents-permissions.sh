#!/usr/bin/env bash
set -euo pipefail

agent_root="${1:?Usage: patch-pi-subagents-permissions.sh <pi-agent-root>}"
source_file="$agent_root/npm/node_modules/pi-subagents/src/agents/agents.ts"

if [[ ! -f "$source_file" ]]; then
  echo "Warning: pi-subagents is not installed at $source_file; skipping compatibility patch." >&2
  exit 0
fi

node - "$source_file" <<'NODE'
const fs = require("node:fs");

const file = process.argv[2];
const source = fs.readFileSync(file, "utf8");
const helper = `function isPiPermissionSystemConfig(value: unknown): boolean {
\tif (!value || typeof value !== "object" || Array.isArray(value)) return false;
\treturn ["defaultPolicy", "tools", "bash", "mcp", "skills", "special"].some((key) => key in value);
}
`;
const oldHelperAnchor = `export type AgentDefaultContext = "fresh" | "fork";\n\n`;
const oldBlock = `\t\tif (frontmatter.permission !== undefined && frontmatter.permissions !== undefined) {
\t\t\tthrow new Error(\`Agent '\${localName}' cannot declare both permission and permissions frontmatter.\`);
\t\t}
\t\tconst permissionSource = frontmatter.permissions ?? frontmatter.permission;
\t\tconst permissions = permissionSource?.trim()
\t\t\t? validatePermissionRules(parseYaml(permissionSource), \`Agent '\${localName}' permissions\`)
\t\t\t: undefined;`;
const newBlock = `\t\tconst nestedPermissionSource = frontmatter.permission?.trim();
\t\tconst nestedPermissionConfig = nestedPermissionSource ? parseYaml(nestedPermissionSource) : undefined;
\t\tconst subagentPermissionSource = frontmatter.permissions?.trim();
\t\tconst permissions = subagentPermissionSource
\t\t\t? validatePermissionRules(parseYaml(subagentPermissionSource), \`Agent '\${localName}' permissions\`)
\t\t\t: nestedPermissionConfig && isPiPermissionSystemConfig(nestedPermissionConfig)
\t\t\t\t? undefined
\t\t\t\t: nestedPermissionConfig
\t\t\t\t\t? validatePermissionRules(nestedPermissionConfig, \`Agent '\${localName}' permissions\`)
\t\t\t\t\t: undefined;`;

if (source.includes("const nestedPermissionSource = frontmatter.permission?.trim();")) {
  process.stdout.write(`Already patched: ${file}\n`);
  process.exit(0);
}
if (!source.includes(oldHelperAnchor) || !source.includes(oldBlock)) {
  throw new Error(`Unsupported pi-subagents source; refusing to patch ${file}`);
}
const patched = source.replace(oldHelperAnchor, `${oldHelperAnchor}${helper}`).replace(oldBlock, newBlock);
fs.writeFileSync(file, patched, "utf8");
process.stdout.write(`Patched: ${file}\n`);
NODE
