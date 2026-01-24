import fs from "fs";
import readline from "readline";

/* ---------- UX helpers ---------- */
const sleep = (ms) => new Promise(res => setTimeout(res, ms));

/* ---------- Load taxonomy ---------- */
function loadTaxonomy(filepath) {
  const text = fs.readFileSync(filepath, "utf8");
  let data = JSON.parse(text);
  if (typeof data === "string") data = JSON.parse(data); // double-encoded
  return data;
}

function escapeCSV(v) {
  const s = String(v ?? "");
  return `"${s.replaceAll('"', '""')}"`;
}

function sanitizeFilename(s) {
  return String(s ?? "export")
    .trim()
    .replaceAll(/[^\w\-]+/g, "_")
    .replaceAll(/_+/g, "_")
    .replaceAll(/^_+|_+$/g, "")
    .slice(0, 80) || "export";
}

/* ---------- Tree utilities ---------- */
function walkCollect(node, out) {
  out.push({
    id: node.id ?? "",
    name: node.name ?? "",
    path: node.path ?? node.name ?? "",
  });
  for (const child of node.children ?? []) walkCollect(child, out);
}

function exportSubtreeToCSV(node, filename) {
  const rows = [];
  walkCollect(node, rows);

  rows.sort((a, b) => a.path.localeCompare(b.path));

  const header = "id,name,path\n";
  const body = rows
    .map(r => `${escapeCSV(r.id)},${escapeCSV(r.name)},${escapeCSV(r.path)}`)
    .join("\n");

  fs.writeFileSync(filename, header + body + "\n", "utf8");
}

/* ---------- Index ---------- */
function buildIndex(roots) {
  const byId = new Map();
  const byName = new Map();

  function index(node) {
    byId.set(String(node.id), node);
    const key = String(node.name ?? "").toLowerCase();
    if (key) {
      if (!byName.has(key)) byName.set(key, []);
      byName.get(key).push(node);
    }
    for (const c of node.children ?? []) index(c);
  }

  roots.forEach(index);
  return { byId, byName };
}

/* ---------- Printing ---------- */
async function printTopLevel(roots) {
  console.log("\nTop-level categories:");
  await sleep(400);
  roots.forEach((r, i) => {
    console.log(`  ${i + 1}. ${r.name}  [id=${r.id}]`);
  });
}

async function printChildren(node) {
  const children = node.children ?? [];
  if (!children.length) {
    console.log("(No children under this node.)");
    return;
  }
  console.log("\nChildren:");
  await sleep(400);
  children.forEach((c, i) => {
    console.log(`  ${i + 1}. ${c.name}  [id=${c.id}]`);
  });
}

/* ---------- Main ---------- */
async function main() {
  console.log("Loading taxonomy...");
  await sleep(500);

  const taxonomy = loadTaxonomy("./taxonomy.json");
  const roots = Array.isArray(taxonomy) ? taxonomy : taxonomy.categories ?? [];

  if (!roots.length) {
    console.error("No root categories found.");
    process.exit(1);
  }

  const { byId, byName } = buildIndex(roots);

  console.log(`Loaded ${roots.length} top-level categories.`);
  await sleep(800);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  const ask = (q) => new Promise(res => rl.question(q, res));

  const virtualRoot = { id: "__ROOT__", name: "ROOT", children: roots };
  const stack = [virtualRoot];

  let exportsDone = 0;
  const maxExports = 2;

  console.log("\nTaxonomy Browser + CSV Export");
  console.log("Navigate, export subtrees, or quit.");
  await sleep(800);

  while (true) {
    const current = stack[stack.length - 1];

    if (current === virtualRoot) {
      await printTopLevel(roots);
    } else {
      console.log(`\nCurrent category: ${current.name}  [id=${current.id}]`);
      await sleep(300);
      await printChildren(current);
    }

    await sleep(300);
    console.log("\nOptions:");
    console.log("  [s] Select / search category");
    console.log("  [e] Export this subtree to CSV");
    console.log("  [u] Go up one level");
    console.log("  [q] Quit");

    const choice = (await ask("\nChoice: ")).trim().toLowerCase();

    if (choice === "q") {
      console.log("\nExiting...");
      await sleep(500);
      rl.close();
      return;
    }

    if (choice === "u") {
      if (stack.length > 1) {
        stack.pop();
        console.log("Moved up one level.");
      } else {
        console.log("Already at top level.");
      }
      await sleep(600);
      continue;
    }

    if (choice === "e") {
      if (exportsDone >= maxExports) {
        console.log("Export limit reached.");
        await sleep(600);
        continue;
      }

      const base = sanitizeFilename(
        current === virtualRoot ? "top_level" : current.name
      );
      const file = `${base}_subtree.csv`;

      const exportNode =
        current === virtualRoot
          ? { name: "Top Level", children: roots }
          : current;

      console.log("Exporting subtree...");
      await sleep(500);

      exportSubtreeToCSV(exportNode, file);
      exportsDone++;

      console.log(`Export complete → ${file}`);
      console.log(`Exports used: ${exportsDone}/${maxExports}`);
      await sleep(800);
      continue;
    }

    if (choice === "s") {
      const children = current.children ?? [];
      if (!children.length) {
        console.log("No children to select here.");
        await sleep(600);
        continue;
      }

      const input = (await ask(
        "Enter child NUMBER, or NAME/ID (direct child only): "
      )).trim();

      const num = Number(input);
      if (Number.isInteger(num) && num >= 1 && num <= children.length) {
        const selected = children[num - 1];
        console.log(`Selected: ${selected.name}`);
        await sleep(600);
        stack.push(selected);
        continue;
      }

      const idMatch = children.find(c => String(c.id) === input);
      if (idMatch) {
        console.log(`Selected: ${idMatch.name}`);
        await sleep(600);
        stack.push(idMatch);
        continue;
      }

      const nameMatch = children.find(
        c => String(c.name).toLowerCase() === input.toLowerCase()
      );
      if (nameMatch) {
        console.log(`Selected: ${nameMatch.name}`);
        await sleep(600);
        stack.push(nameMatch);
        continue;
      }

      console.log("No matching direct child found.");
      await sleep(700);
      continue;
    }

    console.log("Invalid option.");
    await sleep(600);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
