#!/usr/bin/env node

/**
 * Updates docs/MODULES.md by scanning docs/modules/ for module documentation files.
 * Run after creating or updating module documentation.
 *
 * Usage: node scripts/update-index.js
 */

const fs = require("fs");
const path = require("path");

const DOCS_DIR = path.join(process.cwd(), "docs");
const MODULES_DIR = path.join(DOCS_DIR, "modules");
const MODULES_INDEX = path.join(DOCS_DIR, "MODULES.md");

function getModuleFiles() {
  if (!fs.existsSync(MODULES_DIR)) {
    return [];
  }

  return fs
    .readdirSync(MODULES_DIR)
    .filter((file) => file.endsWith(".md"))
    .sort((a, b) => a.localeCompare(b));
}

function generateModulesIndex(moduleFiles) {
  const modulesList = moduleFiles
    .map((file) => `- \`docs/modules/${file}\``)
    .join("\n");

  return `# Modules Documentation

When users ask you to perform tasks, check if any of the available documentation match.

Important:

- When a documentation matches the user's request, this is a BLOCKING REQUIREMENT: read the relevant documentation BEFORE generating any other response about the task
- Do not read a documentation that is already running

Here are the available modules documentation:

${modulesList || "_No modules documented yet._"}
`;
}

function main() {
  // Ensure docs directory exists
  if (!fs.existsSync(DOCS_DIR)) {
    fs.mkdirSync(DOCS_DIR, { recursive: true });
  }

  const moduleFiles = getModuleFiles();
  const content = generateModulesIndex(moduleFiles);

  fs.writeFileSync(MODULES_INDEX, content);
}

main();
