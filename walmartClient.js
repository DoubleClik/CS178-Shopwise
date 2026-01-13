// walmartClient.mjs — Affiliates v2 with inline private key (temporary)
import crypto from 'crypto';
import fs from "fs";

// WARNING / FIXME: Inline key is OK for a quick test, but move it to a .pem asap.
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

// EXACTLY mirror the Java canonicalization
function canonicalizeForSignature({ consumerId, ts, keyVer }) {
  const map = {
    'WM_CONSUMER.ID': String(consumerId).trim(),
    'WM_CONSUMER.INTIMESTAMP': String(ts).trim(),
    'WM_SEC.KEY_VERSION': String(keyVer).trim(),
  };
  const sortedKeys = Object.keys(map).sort(); // lexicographic
  return sortedKeys.map((k) => map[k]).join('\n') + '\n';
}

// Build Walmart security headers (no trailing newline in the payload)
export function generateWalmartHeaders() {
  const id = String(keyData.consumerId).trim();
  const kv = String(keyData.keyVer).trim(); // keep as STRING (e.g., "5")
  const ts = String(Date.now()).trim(); // epoch ms

  const toSign = canonicalizeForSignature({ consumerId: id, ts, keyVer: kv });

  // (Optional) log to verify there's a trailing newline at the end:
  // console.log("toSign (JSON):", JSON.stringify(toSign));

  const signature = crypto
    .sign('RSA-SHA256', Buffer.from(toSign, 'utf8'), {
      key: keyData.privateKeyPem, // PEM private key
      padding: crypto.constants.RSA_PKCS1_PADDING, // PKCS#1 v1.5
      // passphrase: "...",                        // if PEM is encrypted
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

export async function getStoresByZip(zipCode) {
  const url = new URL(
    'https://developer.api.walmart.com/api-proxy/service/affil/product/v2/stores',
  );
  url.searchParams.set('zip', zipCode);

  const res = await fetch(url, {
    method: 'GET',
    headers: generateWalmartHeaders(),
  });

  const text = await res.text();
  if (!res.ok) throw new Error(`Stores HTTP ${res.status}: ${text}`);
  return JSON.parse(text); // { stores: [...] }
}

export async function getProductCatalog(category, count) {
  const url = new URL(
    'https://developer.api.walmart.com/api-proxy/service/affil/product/v2/paginated/items',
  );
  url.searchParams.set('category', category);
  url.searchParams.set('count', count);

  const res = await fetch(url, {
    method: 'GET',
    headers: generateWalmartHeaders(),
  });

  const text = await res.text();
  if (!res.ok) throw new Error(`Stores HTTP ${res.status}: ${text}`);
  fs.writeFileSync(`./walmart_API_Products/${category}.json`, JSON.stringify(text, null, 2));
  return JSON.parse(text);
}

//One-time use to generate taxonomy.json
export async function getTaxonomyID() {
  const url = new URL(
    'https://developer.api.walmart.com/api-proxy/service/affil/product/v2/taxonomy',
  );

  const res = await fetch(url, {
    method: 'GET',
    headers: generateWalmartHeaders(),
  });

  const text = await res.text();
  if (!res.ok) throw new Error(`Stores HTTP ${res.status}: ${text}`);
  fs.writeFileSync("./walmart_API_Taxonomy/taxonomy.json", JSON.stringify(text, null, 2));
  return JSON.parse(text);
}
