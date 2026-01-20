import crypto from "crypto";
import fs from "fs";
import path from "path";

const CATEGORIES_DIR = "Categories";
const OUT_DIR = "walmart_CSVs";

// Walmart endpoint
const BASE = "https://developer.api.walmart.com";
const PAGINATED_PATH = "/api-proxy/service/affil/product/v2/paginated/items";

// Page and Category Ping Delay
const COUNT_PER_PAGE = 500;
const REQUEST_DELAY_MS = 200;   // between pages
const CATEGORY_DELAY_MS = 150;  // between categories

// Retry Attempt Tuning
const FETCH_ATTEMPTS = 5;
const RETRY_BASE_DELAY_MS = 500;

// Output behavior
const EXPORT_PARENT_ROWS_TOO = false;               // false = leaf-ish only
const DEDUPE_WITHIN_EACH_CATEGORY_CSV = true;       // dedupe itemId inside each category CSV
const DEDUPE_WITHIN_SUBTREE_AGG = true;             // dedupe within subtree aggregate
const DEDUPE_MASTER = false;                        // dedupe in global master

// Logging
const MAX_ERROR_BODY_CHARS = 1200;

/* -------------------- AUTH / HEADERS -------------------- */

const keyData = {
  consumerId: '39d025f8-e575-48cf-aa4e-22f89da4c16f',
  keyVer: '5', // keep as STRING; must match walmart.io key version exactly
  privateKeyPem: `-----BEGIN RSA PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC1hpiZMh1pyN6k
oDO95qK3L+/uY3M+sUpcnQkuNdFPBChh3jxEjn3zQLm88rdBTKQVqDD8E7g2KBHX
wYaSiKqqXcBkMkPfEEyTE/I//BjDF5dS+sgR6uIJmfsNVIVkY7laxo0STFCO3G+V
gkHTp8u/lJ5Aa8NSxu4BYlR0wBpze40aHYBeQw/+QuPvZzNeUf5YNC3rs5eId2f5
N0rA2mZfY1myzE6UarW+5+WrWbkR0Bwrvs+8B/S8Jh4QFmh2EDaucisx96MXSH5S
3BuzBxqE9Txo4TKGu0y/aDmRU1Ij5WP88VnURU3vna1UF5n/pPw6InzvcQkeGS1o
thpyvCvtAgMBAAECggEABFOmXm5twvqOQpRa0/Gxo9YX/0iJoZPPdcPhLdF5N/lU
bqdUGeyojxoD41rkHviDXpXH9x9YxwevQp7QcrygjsU6Xv2YuekC3j69ycjcHKqf
UlygHdc3O2r/tHOr1G2RFhITIIbHEqSpqqY9ke7paxtaOQKojqpL/F1jdr8WduM9
WQqbpgk+Hc6PIYVdUeALMX+IGNWbZiX6zqm85IKUdAA4/V0RCMl/j9ySBP6TsT06
5IXK63urXl+AOJh1tHV79GP/waETEc6rQ8Ntn9p3HsUtsx6qiLSky7E2m2L3rdVd
LOzM2vVQDKr0SMGfx4/ZA79OJbLvJnwon9l4WdxmeQKBgQDb4L7sI4FnnD7uAaV5
NTxt6ELJIpgxalTXbGiD6BoGN7LPbRfLJmKP4pGbNkfxtLZKsrTXOE1z5bTurRzY
dsH9pEmhBf7SdYtNrnPZCfOwpZaK/PyVdIggnaAiVYD6Q5urNcTltOA9SLdxGJyE
Ny8GpdB/ItmRCUkru4uk8L3KFQKBgQDTWOaBQRPvrL7sl4nVrTlfaxDTYulFgqSx
j3ag+RBhCwvFVNxb710moIEtThpDnaLNJCc6JQ+QebrsDP7Q49eOxqKbbbLOHGrt
akkeMROg6+MaL7HMAMsjCj7hBnpSjCg94ldHuJ0d8/PB60amIES/TTOyTsssxIlD
HcoX4JsIeQKBgDVHF/wP/mMksPrq2zWreKEJDmW+RDJ1GWm5kvmjW+r1xBYO0R0g
h/FlbPK3DGe86g7fjoI32kyi9FyBBeRNomPbUxv5X+2PHdoM03Vbu/ippvi2pF1y
hymgCBVJsp7xkt7BgJxIX6152TlGRWakGHj75LFpuF40ac52+zdUPiihAoGASmQU
XpKljctkOKruXUPn2eo5te4u5cSia81vmCGS3lWhAwhnuAR86Ue9sFC5detajpKX
LCQ3Ykc2wDeiyawpB5xrSAJI2buu93pd2j60BgSBn4oCLyhoWCEXGOXK0Jt83qt4
xUn6I7zmo+9Iotjg2eU2uSB663sSRYmKxPTOHSECgYEAr9GDqLgORkKWwXhMAe3h
R0tYdGzWqpOiVNi1hcNMGfNwQekfIAM9NVarIib5JYPkSQQQWJZVXcTlR2YZbf9/
P5VgNbNkV23Nq7j926cpbSlgb+UsZOCC5zTaJ0L6oePnK5R38v54y2XC9ccqW6FP
sVP5T4Vx30thw2cpbOY227Q=
-----END RSA PRIVATE KEY-----`,
};

function canonicalizeForSignature({ consumerId, ts, keyVer }) {
    const map = {
        "WM_CONSUMER.ID": String(consumerId).trim(),
        "WM_CONSUMER.INTIMESTAMP": String(ts).trim(),
        "WM_SEC.KEY_VERSION": String(keyVer).trim(),
    };

    const sortedKeys = Object.keys(map).sort();
    return sortedKeys.map((k) => map[k]).join("\n") + "\n";
}

function buildAuthHeaders() {
    const id = String(keyData.consumerId).trim();
    const kv = String(keyData.keyVer).trim();
    const ts = String(Date.now()).trim();

    const toSign = canonicalizeForSignature({
        consumerId: id,
        ts,
        keyVer: kv,
    });

    const signature = crypto
        .sign("RSA-SHA256", Buffer.from(toSign, "utf8"), {
            key: keyData.privateKeyPem,
            padding: crypto.constants.RSA_PKCS1_PADDING,
        })
        .toString("base64");

    return {
        "WM_CONSUMER.ID": id,
        "WM_CONSUMER.INTIMESTAMP": ts,
        "WM_SEC.TIMESTAMP": ts,
        "WM_SEC.KEY_VERSION": kv,
        "WM_SEC.AUTH_SIGNATURE": signature,
        Accept: "application/json",
    };
}

/* -------------------- helpers -------------------- */

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function escapeCSV(value) {
    const s = String(value ?? "");
    return `"${s.replaceAll('"', '""')}"`;
}

function sanitizeFilename(value) {
    return (
        String(value ?? "export")
            .trim()
            .replaceAll(/[^\w\-]+/g, "_")
            .replaceAll(/_+/g, "_")
            .replaceAll(/^_+|_+$/g, "")
            .slice(0, 160) || "export"
    );
}

function formatISO(d) {
    return d.toISOString();
}

function msToHMS(ms) {
    const totalSeconds = Math.floor(ms / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    return `${hours}h ${minutes}m ${seconds}s (${ms} ms)`;
}

function safeTruncate(s, n) {
    const str = String(s ?? "");
    if (str.length <= n) return str;
    return str.slice(0, n) + `... [truncated ${str.length - n} chars]`;
}

/* -------------------- CSV parsing -------------------- */

function parseCSV(text) {
    const rows = [];
    let i = 0;
    let field = "";
    let row = [];
    let inQuotes = false;

    while (i < text.length) {
        const c = text[i];

        if (inQuotes) {
            if (c === '"') {
                if (text[i + 1] === '"') {
                    field += '"';
                    i += 2;
                    continue;
                }
                inQuotes = false;
                i++;
                continue;
            }
            field += c;
            i++;
            continue;
        }

        if (c === '"') {
            inQuotes = true;
            i++;
            continue;
        }

        if (c === ",") {
            row.push(field);
            field = "";
            i++;
            continue;
        }

        if (c === "\n") {
            row.push(field);
            field = "";
            rows.push(row);
            row = [];
            i++;
            continue;
        }

        if (c === "\r") {
            i++;
            continue;
        }

        field += c;
        i++;
    }

    if (field.length > 0 || row.length > 0) {
        row.push(field);
        rows.push(row);
    }

    return rows;
}

function rowsToObjects(rows) {
    if (!rows.length) return [];

    const header = rows[0].map((h) => h.trim());
    const output = [];

    for (let r = 1; r < rows.length; r++) {
        const obj = {};
        for (let c = 0; c < header.length; c++) {
            obj[header[c]] = rows[r][c] ?? "";
        }
        output.push(obj);
    }

    return output;
}

/* -------------------- subtree helpers -------------------- */

function getDepth(pathValue) {
    const s = String(pathValue ?? "").trim();
    if (!s) return Number.POSITIVE_INFINITY;
    return s.split("/").length;
}

function pickSubtreeRoot(objs) {
    const candidates = objs.filter(
        (o) => String(o.id ?? "").trim() && String(o.name ?? "").trim()
    );

    if (!candidates.length) return null;

    candidates.sort((a, b) => {
        const da = getDepth(a.path);
        const db = getDepth(b.path);
        if (da !== db) return da - db;
        return String(a.path ?? "").length - String(b.path ?? "").length;
    });

    return candidates[0];
}

function isParentRow(allRows, row) {
    const p = String(row.path ?? "").trim();
    if (!p) return false;

    const prefix = p.endsWith("/") ? p : (p + "/");
    return allRows.some((o) => String(o.path ?? "").startsWith(prefix));
}

/* -------------------- row conversion -------------------- */

function itemToRow(item, extra) {
    return {
        subtree_id: extra.subtree_id,
        subtree_name: extra.subtree_name,

        category_id: extra.category_id,
        category_name: extra.category_name,
        category_path: extra.category_path,

        item_id: item?.itemId ?? "",
        name: item?.name ?? "",
        msrp: item?.msrp ?? "",
        retail_price: item?.salePrice ?? "",
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
        productTrackingUrl: item?.productTrackingUrl ?? "",
        categoryNode: item?.categoryNode ?? "",
    };
}

function csvHeader(columns) {
    return columns.join(",") + "\n";
}

function rowToCSVLine(row, columns) {
    return columns.map((k) => escapeCSV(row[k])).join(",") + "\n";
}

/* -------------------- Walmart fetching -------------------- */

async function fetchPage(url, attempts = FETCH_ATTEMPTS) {
    for (let i = 0; i < attempts; i++) {
        const headers = buildAuthHeaders();
        const res = await fetch(url, { headers });

        if (res.ok) {
            return await res.json();
        }

        const status = res.status;
        const statusText = res.statusText;
        const body = await res.text().catch(() => "");

        if (status === 429 || (status >= 500 && status <= 599)) {
            const backoff = RETRY_BASE_DELAY_MS * Math.pow(2, i);
            await sleep(backoff);
            continue;
        }

        const err = new Error(`HTTP ${status} ${statusText}`);
        err.httpStatus = status;
        err.httpStatusText = statusText;
        err.url = url;
        err.responseBody = safeTruncate(body, MAX_ERROR_BODY_CHARS);
        throw err;
    }

    const err = new Error(`Failed after ${attempts} attempts`);
    err.url = url;
    throw err;
}

async function fetchAllItemsForCategory(categoryId) {
    let url = new URL(BASE + PAGINATED_PATH);
    url.searchParams.set("category", categoryId);
    url.searchParams.set("count", String(COUNT_PER_PAGE));

    const allItems = [];

    while (true) {
        const data = await fetchPage(url.toString());
        const items = Array.isArray(data?.items) ? data.items : [];

        allItems.push(...items);

        if (!data?.nextPageExist || !data?.nextPage) {
            break;
        }

        url = new URL(
            data.nextPage.startsWith("http")
                ? data.nextPage
                : BASE + data.nextPage
        );

        await sleep(REQUEST_DELAY_MS);
    }

    return allItems;
}

/* -------------------- Logging / finalization -------------------- */

const runState = {
    startedAt: new Date(),
    endedAt: null,
    exitReason: "completed",
    subtreeFilesProcessed: 0,
    categoryRowsAttempted: 0,
    categoryRowsSucceeded: 0,
    categoryRowsFailed: 0,
    failures: [],
};

let finalized = false;
let masterStreamRef = null;

function writeRunLogFile(outPath) {
    const endedAt = runState.endedAt ?? new Date();
    const elapsedMs = endedAt.getTime() - runState.startedAt.getTime();

    const logFolder = path.resolve(outPath);
    if (!fs.existsSync(logFolder)) {
        fs.mkdirSync(logFolder, { recursive: true });
    }

    const logName = `run_log_${sanitizeFilename(formatISO(runState.startedAt))}.json`;
    const logPath = path.join(logFolder, logName);

    const payload = {
        startedAt: formatISO(runState.startedAt),
        endedAt: formatISO(endedAt),
        elapsed: msToHMS(elapsedMs),
        exitReason: runState.exitReason,
        counts: {
            subtreeFilesProcessed: runState.subtreeFilesProcessed,
            categoryRowsAttempted: runState.categoryRowsAttempted,
            categoryRowsSucceeded: runState.categoryRowsSucceeded,
            categoryRowsFailed: runState.categoryRowsFailed,
        },
        failures: runState.failures,
    };

    fs.writeFileSync(logPath, JSON.stringify(payload, null, 4), "utf8");
    console.log(`Log written: ${OUT_DIR}/${path.basename(logPath)}`);
}

function finalizeAndExit(outPath, reason, code = 0) {
    if (finalized) {
        process.exit(code);
        return;
    }

    finalized = true;
    runState.exitReason = reason ?? runState.exitReason;
    runState.endedAt = new Date();

    try {
        if (masterStreamRef && !masterStreamRef.closed) {
            masterStreamRef.end();
        }
    } catch (_) {}

    try {
        writeRunLogFile(outPath);
    } catch (e) {
        console.error("Failed to write log file:", e);
    }

    process.exit(code);
}

function registerExitHandlers(outPath) {
    process.on("SIGINT", () => finalizeAndExit(outPath, "SIGINT (Ctrl+C)", 130));
    process.on("SIGTERM", () => finalizeAndExit(outPath, "SIGTERM", 143));

    process.on("uncaughtException", (err) => {
        runState.failures.push({
            type: "uncaughtException",
            message: String(err?.message ?? err),
            stack: String(err?.stack ?? ""),
            when: formatISO(new Date()),
        });
        finalizeAndExit(outPath, "uncaughtException", 1);
    });

    process.on("unhandledRejection", (reason) => {
        runState.failures.push({
            type: "unhandledRejection",
            message: String(reason?.message ?? reason),
            stack: String(reason?.stack ?? ""),
            when: formatISO(new Date()),
        });
        finalizeAndExit(outPath, "unhandledRejection", 1);
    });
}

/* -------------------- main -------------------- */

async function main() {
    const categoriesPath = path.resolve(process.cwd(), CATEGORIES_DIR);
    const outPath = path.resolve(process.cwd(), OUT_DIR);

    registerExitHandlers(outPath);

    if (!fs.existsSync(categoriesPath)) {
        throw new Error(`Missing folder: ${categoriesPath}`);
    }

    if (!fs.existsSync(outPath)) {
        fs.mkdirSync(outPath, { recursive: true });
    }

    const subtreeFiles = fs
        .readdirSync(categoriesPath)
        .filter((f) => f.toLowerCase().endsWith(".csv"));

    if (!subtreeFiles.length) {
        throw new Error(`No .csv files found in ${categoriesPath}`);
    }

    const columns = [
        "subtree_id",
        "subtree_name",
        "category_id",
        "category_name",
        "category_path",
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
        "productTrackingUrl",
        "categoryNode",
    ];

    const masterFile = path.join(outPath, "ALL_SUBTREES_PRODUCTS.csv");
    const masterStream = fs.createWriteStream(masterFile, { encoding: "utf8" });
    masterStreamRef = masterStream;
    masterStream.write(csvHeader(columns));

    const seenMaster = DEDUPE_MASTER ? new Set() : null;
    let masterCount = 0;

    for (const file of subtreeFiles) {
        const subtreeCsvPath = path.join(categoriesPath, file);
        const text = fs.readFileSync(subtreeCsvPath, "utf8");

        const parsed = parseCSV(text);
        const objsRaw = rowsToObjects(parsed);

        if (!objsRaw.length) {
            continue;
        }

        const root = pickSubtreeRoot(objsRaw);
        const subtree_name = root?.name ?? path.basename(file, ".csv");
        const subtree_id = root?.id ?? "";

        const subtreeLabel = sanitizeFilename(`${subtree_name}_${subtree_id || "unknown"}`);

        // Subtree aggregate CSV
        const subtreeAggFile = path.join(outPath, `${subtreeLabel}__ALL.csv`);
        const subtreeAggStream = fs.createWriteStream(subtreeAggFile, { encoding: "utf8" });
        subtreeAggStream.write(csvHeader(columns));

        const seenSubtreeAgg = DEDUPE_WITHIN_SUBTREE_AGG ? new Set() : null;
        let subtreeAggCount = 0;

        const rows = objsRaw
            .map((o) => ({
                id: String(o.id ?? "").trim(),
                name: String(o.name ?? "").trim(),
                path: String(o.path ?? "").trim(),
            }))
            .filter((o) => o.id && o.name);

        for (const row of rows) {
            const parent = isParentRow(rows, row);

            if (!EXPORT_PARENT_ROWS_TOO && parent) {
                continue;
            }

            runState.categoryRowsAttempted++;

            await sleep(CATEGORY_DELAY_MS);

            let items;
            try {
                items = await fetchAllItemsForCategory(row.id);
                runState.categoryRowsSucceeded++;
            } catch (e) {
                runState.categoryRowsFailed++;

                runState.failures.push({
                    type: "categoryFetchFailed",
                    subtreeFile: file,
                    subtreeName: subtree_name,
                    subtreeId: subtree_id,
                    categoryId: row.id,
                    categoryName: row.name,
                    categoryPath: row.path,
                    message: String(e?.message ?? e),
                    httpStatus: e?.httpStatus ?? null,
                    url: e?.url ?? null,
                    responseBody: e?.responseBody ?? null,
                    stack: String(e?.stack ?? ""),
                    when: formatISO(new Date()),
                });

                console.error(`Failed category ${row.id} (${row.name}): ${e.message}`);
                continue;
            }

            const categoryLabel = sanitizeFilename(
                `${subtree_name}_${subtree_id}__${row.name}_${row.id}`
            );
            const categoryFile = path.join(outPath, `${categoryLabel}.csv`);
            const categoryStream = fs.createWriteStream(categoryFile, { encoding: "utf8" });
            categoryStream.write(csvHeader(columns));

            const seenCategory = DEDUPE_WITHIN_EACH_CATEGORY_CSV ? new Set() : null;
            let categoryCount = 0;

            for (const item of items) {
                const itemId = String(item?.itemId ?? "");
                if (!itemId) continue;

                if (seenCategory) {
                    if (seenCategory.has(itemId)) continue;
                    seenCategory.add(itemId);
                }

                const outRow = itemToRow(item, {
                    subtree_id,
                    subtree_name,
                    category_id: row.id,
                    category_name: row.name,
                    category_path: row.path,
                });

                // Per-category CSV
                categoryStream.write(rowToCSVLine(outRow, columns));
                categoryCount++;

                // Subtree aggregate (dedup optional)
                if (seenSubtreeAgg) {
                    if (!seenSubtreeAgg.has(itemId)) {
                        seenSubtreeAgg.add(itemId);
                        subtreeAggStream.write(rowToCSVLine(outRow, columns));
                        subtreeAggCount++;
                    }
                } else {
                    subtreeAggStream.write(rowToCSVLine(outRow, columns));
                    subtreeAggCount++;
                }

                // Master (dedup optional)
                if (seenMaster) {
                    if (!seenMaster.has(itemId)) {
                        seenMaster.add(itemId);
                        masterStream.write(rowToCSVLine(outRow, columns));
                        masterCount++;
                    }
                } else {
                    masterStream.write(rowToCSVLine(outRow, columns));
                    masterCount++;
                }
            }

            await new Promise((resolve) => categoryStream.end(resolve));

            console.log(
                `Wrote category CSV: ${path.basename(categoryFile)} (${categoryCount} rows)`
            );
        }

        await new Promise((resolve) => subtreeAggStream.end(resolve));

        runState.subtreeFilesProcessed++;

        console.log(
            `Wrote subtree aggregate CSV: ${path.basename(subtreeAggFile)} (${subtreeAggCount} rows)`
        );
    }

    await new Promise((resolve) => masterStream.end(resolve));
    console.log(`Wrote master CSV: ${path.basename(masterFile)} (${masterCount} rows)`);

    finalizeAndExit(outPath, "completed", 0);
}

main().catch((err) => {
    console.error(err);
    finalizeAndExit(path.resolve(process.cwd(), OUT_DIR), "main() catch", 1);
});
