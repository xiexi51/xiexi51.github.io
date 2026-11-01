const fs = require("node:fs");
const path = require("node:path");
const { PurgeCSS } = require("purgecss");
const config = require("../purgecss.config.js");

// The v6 CLI duplicates relative Windows paths when writing to `output`.
// Write each API result to its original CSS file on both Windows and Linux.
async function main() {
  const cssRoot = path.resolve("_site/assets/css") + path.sep;
  const results = await new PurgeCSS().purge(config);
  if (results.length === 0) throw new Error("No generated CSS files were found.");
  for (const result of results) {
    if (!result.file) throw new Error("PurgeCSS returned a result without a filename.");
    const filename = path.resolve(result.file);
    if (!filename.startsWith(cssRoot)) throw new Error(`Unexpected CSS destination: ${filename}`);
    fs.writeFileSync(filename, result.css, "utf8");
  }
  console.log(`Purged ${results.length} CSS files.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
