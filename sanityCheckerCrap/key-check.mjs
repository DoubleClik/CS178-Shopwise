import fs from 'fs';
import crypto from 'crypto';

const pem = fs.readFileSync('./private_key.pem', 'utf8'); // or your inline string
try {
  const ts = String(Date.now());
  const toSign = `your-consumer-id\n${ts}\nyour-key-version`;
  crypto.sign('RSA-SHA256', Buffer.from(toSign), {
    key: pem,
    padding: crypto.constants.RSA_PKCS1_PADDING,
    // passphrase: "if-you-set-one",
  });
  console.log('✅ Key parsed and signature generated.');
} catch (e) {
  console.error('❌ Still failing:', e.message);
}
