// run.js — tiny CLI to print results
import { getStoresByZip, getProductCatalog, getTaxonomyID } from './walmartClient.js';

const [, , cmd, arg1, arg2] = process.argv;

try {
  if (cmd === 'stores') {
    const zip = arg1 || '92507';
    const data = await getStoresByZip(zip);

    console.table(data);
  } else if (cmd === 'lookup') {
    const category = arg1 || '';
    const count = arg2 || 2;
    const data = await getProductCatalog(category, count);
    console.log(data);
  } else if (cmd === 'taxonomy') {
    const category = arg1 || '';
    const data = await getTaxonomyID(category);
    console.log(data);
  } else {
    console.log(`Usage:
  node run.js stores <ZIP>`);
  }
} catch (e) {
  console.error('Request failed:', e.message);
}
