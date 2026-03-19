/**
 * generateTaxonomy.js
 *
 * Downloads the Walmart product taxonomy and saves it to JSON.
 * Run this first, then use browseTaxonomyExport.js to pick which
 * subtrees you want to export as CSVs.
 *
 * Needs WM_CONSUMER_ID, WM_KEY_VERSION, WM_PRIVATE_KEY in .env.
 */

import dotenv from 'dotenv';
dotenv.config();
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);

const BASE = 'https://developer.api.walmart.com';
const TAXONOMY_PATH = '/api-proxy/service/affil/product/v2/taxonomy';

function loadCredentials() {
  const consumerId = process.env.WM_CONSUMER_ID;
  const keyVer = process.env.WM_KEY_VERSION;
  const privateKeyPem = process.env.WM_PRIVATE_KEY;

  if (!consumerId || !keyVer || !privateKeyPem) {
    throw new Error(
      'Missing Walmart credentials in .env: WM_CONSUMER_ID, WM_KEY_VERSION, WM_PRIVATE_KEY',
    );
  }

  return { consumerId, keyVer, privateKeyPem };
}

// same signing logic as fetchProducts.js - Walmart needs this on every request
function buildAuthHeaders(creds) {
  const id = String(creds.consumerId).trim();
  const kv = String(creds.keyVer).trim();
  const ts = String(Date.now()).trim();

  const fields = {
    'WM_CONSUMER.ID': id,
    'WM_CONSUMER.INTIMESTAMP': ts,
    'WM_SEC.KEY_VERSION': kv,
  };

  const canonicalized =
    Object.keys(fields)
      .sort()
      .map((k) => fields[k])
      .join('\n') + '\n';

  const signature = crypto
    .sign('RSA-SHA256', Buffer.from(canonicalized, 'utf8'), {
      key: creds.privateKeyPem,
      padding: crypto.constants.RSA_PKCS1_PADDING,
    })
    .toString('base64');

  return {
    'WM_CONSUMER.ID': id,
    'WM_CONSUMER.INTIMESTAMP': ts,
    'WM_SEC.TIMESTAMP': ts,
    'WM_SEC.KEY_VERSION': kv,
    'WM_SEC.AUTH_SIGNATURE': signature,
    Accept: 'application/json',
  };
}

// fetches the taxonomy and saves two files: the raw response and a pretty-printed version
export async function run(opts = {}) {
  const outPretty =
    opts.outPretty ?? path.resolve(process.cwd(), 'taxonomy.json');
  const outRaw =
    opts.outRaw ?? path.resolve(process.cwd(), 'taxonomy_raw.json');

  const creds = loadCredentials();

  const url = new URL(BASE + TAXONOMY_PATH);
  url.searchParams.set('format', 'json');

  console.log('Requesting taxonomy:');
  console.log(url.toString(), '\n');

  const headers = buildAuthHeaders(creds);
  const res = await fetch(url.toString(), { headers });
  const text = await res.text();

  // Always save raw response for debugging
  fs.writeFileSync(outRaw, text, 'utf8');
  console.log(`Saved raw response to: ${outRaw}`);

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${res.statusText}\n${text}`);
  }

  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    throw new Error(
      `Response was not valid JSON. Raw response saved to ${path.basename(outRaw)}.\nParse error: ${e.message}`,
    );
  }

  fs.writeFileSync(outPretty, JSON.stringify(data, null, 4), 'utf8');
  console.log(`Saved taxonomy to: ${outPretty}`);

  return data;
}

if (process.argv[1] === __filename) {
  run().catch((e) => {
    console.error('\nFailed to download taxonomy:', e.message);
    process.exit(1);
  });
}
