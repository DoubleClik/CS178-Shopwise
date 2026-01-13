import fs from "fs";
import path from "path";
import readline from "readline";

const FOLDER = "walmart_API_Products";

/* ---------- helpers ---------- */
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function escapeCSV(v) {
  const s = String(v ?? "");
  return `"${s.replaceAll('"', '""')}"`;
}

function parsePossiblyDoubleEncodedJson(text) {
  let data = JSON.parse(text);
  if (typeof data === "string") data = JSON.parse(data);
  return data;
}

function buildRow(item) {
  const retailPrice = item?.salePrice ?? "";

  return {
    item_id: item?.itemId ?? "",
    name: item?.name ?? "",
    msrp: item?.msrp ?? "",
    retail_price: retailPrice,
    upc: item?.upc ?? "",
    shortDescription: item?.shortDescription ?? "",
    longDescription: item?.longDescription ?? "",
    brandName: item?.brandName ?? "",
    thumbnailImage: item?.thumbnailImage ?? "",
    mediumImage: item?.mediumImage ?? "",
    largeImage: item?.largeImage ?? "",
    color: item?.color ?? "",
    customerRating: item?.customerRating ?? "",
    stock: item?.stock ?? "",
  };
}

function toCSV(rows) {
  const header = [
    "item_id",
    "name",
    "msrp",
    "retail_price",
    "upc",
    "shortDescription",
    "longDescription",
    "brandName",
    "thumbnailImage",
    "mediumImage",
    "largeImage",
    "color",
    "customerRating",
    "stock",
  ].join(",");

  const lines = rows.map((r) =>
    [
      r.item_id,
      r.name,
      r.msrp,
      r.retail_price,
      r.upc,
      r.shortDescription,
      r.longDescription,
      r.brandName,
      r.thumbnailImage,
      r.mediumImage,
      r.largeImage,
      r.color,
      r.customerRating,
      r.stock,
    ]
      .map(escapeCSV)
      .join(",")
  );

  return header + "\n" + lines.join("\n") + "\n";
}

/* ---------- main ---------- */
async function main() {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = (q) => new Promise((res) => rl.question(q, res));

  console.log(`Folder: ./${FOLDER}`);
  await sleep(250);

  const answer = (await ask("Skip items where stock is 'Not available'? (y/n): "))
    .trim()
    .toLowerCase();

  const skipNotAvailable = answer === "y" || answer === "yes";
  console.log(skipNotAvailable ? "✓ Will skip 'Not available' items." : "✓ Will include all items.");
  await sleep(400);

  rl.close();

  const folderPath = path.resolve(process.cwd(), FOLDER);
  if (!fs.existsSync(folderPath)) {
    console.error(`ERROR: Folder not found: ${folderPath}`);
    process.exit(1);
  }

  const files = fs
    .readdirSync(folderPath)
    .filter((f) => f.toLowerCase().endsWith(".json"));

  if (files.length === 0) {
    console.error(`ERROR: No .json files found in ${folderPath}`);
    process.exit(1);
  }

  for (const file of files) {
    const jsonPath = path.join(folderPath, file);
    const csvPath = path.join(folderPath, file.replace(/\.json$/i, ".csv"));

    try {
      const text = fs.readFileSync(jsonPath, "utf8");
      const data = parsePossiblyDoubleEncodedJson(text);

      const items = Array.isArray(data?.items) ? data.items : [];
      const rows = [];

      for (const item of items) {
        const stock = String(item?.stock ?? "");
        if (skipNotAvailable && stock === "Not available") continue;
        rows.push(buildRow(item));
      }

      const csv = toCSV(rows);
      fs.writeFileSync(csvPath, csv, "utf8");

      console.log(`${file} → ${path.basename(csvPath)} (${rows.length} rows)`);
      await sleep(150);
    } catch (err) {
      console.error(`Failed on ${file}: ${err?.message ?? err}`);
    }
  }

  console.log("Done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
