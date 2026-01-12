import fs from "fs";

function loadTaxonomy(filepath) {
  const text = fs.readFileSync(filepath, "utf8");

  // First parse
  let data = JSON.parse(text);

  // Handle double-encoded JSON
  if (typeof data === "string") {
    data = JSON.parse(data);
  }

  return data;
}

const taxonomy = loadTaxonomy("./taxonomy.json");

// Root categories
const topLevel = Array.isArray(taxonomy)
  ? taxonomy
  : (taxonomy.categories ?? []);

// Build CSV
const header = "id,name\n";
const rows = topLevel.map(node =>
  `"${String(node.id).replaceAll('"','""')}","${String(node.name).replaceAll('"','""')}"`
);

// Write CSV only
fs.writeFileSync(
  "top_level_categories.csv",
  header + rows.join("\n") + "\n",
  "utf8"
);
