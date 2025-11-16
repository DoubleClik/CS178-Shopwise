// run.js — tiny CLI to print results
import { getStoresByZip, getStoresByCoord } from './walmartClient.js';

const [, , cmd, arg1, arg2] = process.argv;

try {
  if (cmd === 'stores') {
    const zip = arg1 || '92507';
    const data = await getStoresByZip(zip);

    console.table(data);
  } else {
    console.log(`Usage:
  node run.js stores <ZIP>`);
  }
} catch (e) {
  console.error('Request failed:', e.message);
}
