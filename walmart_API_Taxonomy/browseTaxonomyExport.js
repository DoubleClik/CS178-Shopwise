import fs from "fs";
import readline from "readline";

/* ---------- UX helpers ---------- */
const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

/* ---------- Sorting helper (presentation only) ---------- */
function sortByName(nodes = []) {
  return [...nodes].sort((a, b) =>
    String(a.name ?? "").localeCompare(String(b.name ?? ""), undefined, {
      sensitivity: "base",
    })
  );
}

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
  return (
    String(s ?? "export")
      .trim()
      .replaceAll(/[^\w\-]+/g, "_")
      .replaceAll(/_+/g, "_")
      .replaceAll(/^_+|_+$/g, "")
      .slice(0, 80) || "export"
  );
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

  // Sort exported rows by path (keeps CSV stable / readable)
  rows.sort((a, b) => String(a.path).localeCompare(String(b.path)));

  const header = "id,name,path\n";
  const body = rows
    .map((r) => `${escapeCSV(r.id)},${escapeCSV(r.name)},${escapeCSV(r.path)}`)
    .join("\n");

  fs.writeFileSync(filename, header + body + "\n", "utf8");
}

/* ---------- Printing (alphabetical) ---------- */
async function printTopLevel(roots) {
  const sorted = sortByName(roots);

  console.log("\nTop-level categories (A → Z):");
  await sleep(400);

  sorted.forEach((r, i) => {
    console.log(`  ${i + 1}. ${r.name ?? "(no name)"}  [id=${r.id ?? "?"}]`);
  });

  return sorted; // IMPORTANT: return the sorted list used for numbering
}

async function printChildren(node) {
  const sorted = sortByName(node.children ?? []);

  if (!sorted.length) {
    console.log("(No children under this node.)");
    return sorted;
  }

  console.log("\nChildren (A → Z):");
  await sleep(400);

  sorted.forEach((c, i) => {
    console.log(`  ${i + 1}. ${c.name ?? "(no name)"}  [id=${c.id ?? "?"}]`);
  });

  return sorted; // IMPORTANT: return the sorted list used for numbering
}

/* ---------- Main ---------- */
async function main() {
  console.log("Loading taxonomy...");
  await sleep(500);

  const taxonomy = loadTaxonomy("./taxonomy.json");
  const roots = Array.isArray(taxonomy) ? taxonomy : taxonomy.categories ?? [];

  if (!roots.length) {
    console.error("No root categories found. Check taxonomy.json shape.");
    process.exit(1);
  }

  console.log(`Loaded ${roots.length} top-level categories.`);
  await sleep(800);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  const ask = (q) => new Promise((res) => rl.question(q, res));

  // Navigation stack: start at "virtual root" that holds top-level as children.
  const virtualRoot = {
    id: "__ROOT__",
    name: "ROOT",
    path: "",
    children: roots,
  };
  const stack = [virtualRoot];

  let exportsDone = 0;
  const maxExports = 2;

  console.log("\nTaxonomy Browser + CSV Export");
  console.log("Type category NUMBER (from list), or export/go up/quit.\n");
  await sleep(800);

  while (true) {
    const current = stack[stack.length - 1];

    // Keep the exact list we printed so numbering selection NEVER breaks.
    let visibleList = [];

    if (current === virtualRoot) {
      visibleList = await printTopLevel(roots); // sorted list returned
    } else {
      console.log(
        `\nCurrent category: ${current.name ?? "(no name)"}  [id=${
          current.id ?? "?"
        }]`
      );
      await sleep(300);
      visibleList = await printChildren(current); // sorted list returned
    }

    await sleep(300);
    console.log("\nOptions:");
    console.log("  [s] Select a child category (by NUMBER / name / id)");
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
          ? { id: "__TOP__", name: "Top Level", path: "", children: roots }
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
      if (!visibleList.length) {
        console.log("No children to select here. Try going up [u].");
        await sleep(600);
        continue;
      }

      const input = (await ask(
        "Enter NUMBER from the list, or a child NAME/ID: "
      )).trim();

      // NUMBER selection (guaranteed safe because visibleList matches printed list)
      const num = Number(input);
      if (Number.isInteger(num) && num >= 1 && num <= visibleList.length) {
        const selected = visibleList[num - 1];
        console.log(`Selected: ${selected.name ?? "(no name)"}`);
        await sleep(600);
        stack.push(selected);
        continue;
      }

      // ID match among visible children
      const idMatch = visibleList.find((c) => String(c.id) === input);
      if (idMatch) {
        console.log(`Selected: ${idMatch.name ?? "(no name)"}`);
        await sleep(600);
        stack.push(idMatch);
        continue;
      }

      // Name match among visible children
      const key = input.toLowerCase();
      const nameMatch = visibleList.find(
        (c) => String(c.name ?? "").toLowerCase() === key
      );
      if (nameMatch) {
        console.log(`Selected: ${nameMatch.name ?? "(no name)"}`);
        await sleep(600);
        stack.push(nameMatch);
        continue;
      }

      console.log("No matching direct child found.");
      await sleep(700);
      continue;
    }

    console.log("Invalid option. Please choose s/e/u/q.");
    await sleep(600);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
