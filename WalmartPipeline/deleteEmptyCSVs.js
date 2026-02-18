import fs from 'fs';
import path from 'path';

const TARGET_DIR = 'WalmartPipeline/walmart_CSVs';

/* -------------------- helpers -------------------- */

function isEmptyCSV(filePath) {
  const stat = fs.statSync(filePath);

  // Truly empty file
  if (stat.size === 0) {
    return true;
  }

  const content = fs.readFileSync(filePath, 'utf8').trim();
  if (!content) {
    return true;
  }

  // Header-only CSV (1 line)
  const lines = content.split(/\r?\n/);
  return lines.length <= 1;
}

/* -------------------- main -------------------- */

function main() {
  const dirPath = path.resolve(process.cwd(), TARGET_DIR);

  if (!fs.existsSync(dirPath)) {
    console.error(`Folder not found: ${dirPath}`);
    process.exit(1);
  }

  const files = fs.readdirSync(dirPath);

  let deleted = 0;
  let checked = 0;

  for (const file of files) {
    if (!file.toLowerCase().endsWith('.csv')) {
      continue;
    }

    const filePath = path.join(dirPath, file);
    checked++;

    try {
      if (isEmptyCSV(filePath)) {
        fs.unlinkSync(filePath);
        deleted++;
        console.log(`Deleted empty CSV: ${file}`);
      }
    } catch (e) {
      console.warn(`Failed to process ${file}: ${e.message}`);
    }
  }

  console.log(`\nChecked ${checked} CSV files`);
  console.log(`Deleted ${deleted} empty CSV files`);
}

main();
