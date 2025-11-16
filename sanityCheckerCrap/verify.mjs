import crypto from 'crypto';
import fs from 'fs';

const consumerId = '39d025f8-e575-48cf-aa4e-22f89da4c16f';
const keyVer = '5';
const ts = String(Date.now());

const payload = `${consumerId}\n${ts}\n${keyVer}`;
const privatePem = fs.readFileSync('./private_key.pem', 'utf8'); // OR your inline string
const publicPem = fs.readFileSync('./public_key.pem', 'utf8');

// sign (exactly like your client)
const sigB64 = crypto
  .sign('RSA-SHA256', Buffer.from(payload), {
    key: privatePem,
    padding: crypto.constants.RSA_PKCS1_PADDING,
  })
  .toString('base64');

// verify with the public key from the portal
const ok = crypto.verify(
  'RSA-SHA256',
  Buffer.from(payload),
  { key: publicPem, padding: crypto.constants.RSA_PKCS1_PADDING },
  Buffer.from(sigB64, 'base64'),
);

console.log('verify:', ok ? 'OK ✅' : 'FAIL ❌');
console.log({ toSign: payload, sigLen: sigB64.length });
