/**
 * runner.js
 *
 * Runs the Walmart and Kroger pipelines. You can run all stages, just one
 * pipeline, or pick specific stages by name.
 *
 * To add a new stage later (like Supabase import), just append an object
 * to the STAGES array - there's already a commented-out placeholder for that.
 *
 * Usage:
 *   node runner.js --all
 *   node runner.js --walmart
 *   node runner.js --kroger --zipcode=92507
 *   node runner.js --all --dry-run
 *   node runner.js --help
 */

import dotenv from 'dotenv';
dotenv.config();

import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { run as walmartFetch } from './WalmartPipeline/fetchProducts.js';
import { importWalmart, importKroger, importKrogerStores } from './supabase_import.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const argv = process.argv.slice(2);

function flag(name) {
  return argv.includes(name);
}
function opt(prefix, def) {
  return (
    (argv.find((a) => a.startsWith(prefix)) ?? '').replace(prefix, '') || def
  );
}

const runAll = flag('--all');
const runWalmart = flag('--walmart') || runAll;
const runKroger = flag('--kroger') || runAll;
const runSupabase = flag('--supabase') || runAll;
const runReclassify = flag('--reclassify'); // re-run classifier on existing walmart_CSVs without re-fetching
const runFindStores = flag('--find-stores'); // just run kroger:stores, skip everything else
const isDryRun = flag('--dry-run');
const useLLM = flag('--llm');
const continueErr = flag('--continue-on-error');
const showHelp = flag('--help') || flag('-h') || argv.length === 0;

const zipcode = opt('--zipcode=', '');
const stores = opt('--stores=', '10');
const radius = opt('--radius=', '25');
const llmModel = opt('--model=', 'llama3.2:1b');
const llmWorkers = opt('--workers=', '8');
const stagesArg = opt('--stages=', '');

// runs a subprocess and waits for it to finish
// stdio: 'inherit' pipes the output straight to our terminal
function spawn_(cmd, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      stdio: 'inherit',
      env: process.env,
      cwd: __dirname,
    });
    child.on('close', (code) => {
      if (code === 0 || code === null) resolve();
      else
        reject(
          new Error(`"${cmd} ${args.join(' ')}" exited with code ${code}`),
        );
    });
    child.on('error', (err) => reject(new Error(`${cmd}: ${err.message}`)));
  });
}

// Each stage has an id, label, group, and a run() that returns a Promise.
// To add a new stage later just append another object to this array.
const STAGES = [
  {
    id: 'walmart:fetch',
    label: 'Fetch Walmart products from category CSVs',
    group: 'walmart',
    run: async () => {
      // calls into fetchProducts.js directly instead of spawning a subprocess
      // pass a config object to run() if you want to change the output dir, etc.
      const stats = await walmartFetch();
      console.log(
        `\n  Succeeded: ${stats.categoryRowsSucceeded} categories` +
          ` | Failed: ${stats.categoryRowsFailed}` +
          ` | Subtrees: ${stats.subtreeFilesProcessed}`,
      );
    },
  },

  {
    id: 'walmart:classify',
    label: 'Classify Walmart products as ingredients (Python)',
    group: 'walmart',
    // reads from walmart_CSVs/, writes to classified_ingredients.csv
    // no LLM by default - add --llm to enable ollama, --model=<name> to change the model
    run: () =>
      spawn_('python3', [
        'WalmartPipeline/classify_ingredients.py',
        'WalmartPipeline/walmart_CSVs',
        '-o',
        'WalmartPipeline/classified_ingredients.csv',
        ...(useLLM ? ['-m', llmModel, '-w', llmWorkers] : ['--no-llm']),
      ]),
  },

  {
    id: 'kroger:build',
    label: 'Build Kroger food catalogue for stores near a zip code',
    group: 'kroger',
    // --zipcode is required - kroger_catalogue.js will error if it's missing
    run: () => {
      if (!zipcode) throw new Error('kroger:build requires --zipcode=XXXXX');
      return spawn_('node', [
        'KrogerPipeline/kroger_catalogue.js',
        `--zipcode=${zipcode}`,
        `--stores=${stores}`,
        `--radius=${radius}`,
        ...(isDryRun ? ['--dry-run'] : []),
      ]);
    },
  },

  {
    id: 'kroger:stores',
    label: 'Find nearest Kroger stores and save to Supabase',
    group: 'kroger',
    run: () => {
      if (!zipcode) throw new Error('kroger:stores requires --zipcode=XXXXX');
      return importKrogerStores({ zipcode, stores: parseInt(stores, 10), dryRun: isDryRun });
    },
  },

  {
    id: 'supabase:walmart',
    label: 'Import Walmart ingredients into Supabase',
    group: 'supabase',
    run: () => importWalmart({ dryRun: isDryRun }),
  },

  {
    id: 'supabase:kroger',
    label: 'Import Kroger catalogue into Supabase',
    group: 'supabase',
    run: () => importKroger({ dryRun: isDryRun }),
  },
];

function selectStages() {
  const validIds = new Set(STAGES.map((s) => s.id));

  // --reclassify just re-runs the classifier on already-fetched CSVs
  if (runReclassify) return STAGES.filter((s) => s.id === 'walmart:classify');

  // --find-stores just runs the store search, no catalogue or ingredient importing
  if (runFindStores) return STAGES.filter((s) => s.id === 'kroger:stores');

  // --stages=... takes priority if given
  if (stagesArg) {
    const requested = stagesArg
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    for (const id of requested) {
      if (!validIds.has(id)) {
        console.error(
          `Unknown stage: "${id}". Valid stages: ${[...validIds].join(', ')}`,
        );
        process.exit(1);
      }
    }
    return STAGES.filter((s) => requested.includes(s.id));
  }

  return STAGES.filter((s) => {
    if (s.group === 'walmart' && !runWalmart) return false;
    if (s.group === 'kroger' && !runKroger) return false;
    if (s.group === 'supabase' && !runSupabase) return false;
    return true;
  });
}

function printHelp() {
  const stageList = STAGES.map((s) => `  ${s.id.padEnd(22)}${s.label}`).join(
    '\n',
  );
  console.log(`
Shopwise Pipeline Runner
=====================================================

Usage:
  node runner.js [flags]

Flags:
  --all                  Run all stages (kroger:enrich skipped unless --zipcode given)
  --walmart              Run walmart:fetch and walmart:classify
  --reclassify           Re-run walmart:classify on existing CSVs (skips the API fetch)
  --find-stores          Just find nearest stores and save to Supabase (requires --zipcode)
  --kroger               Run kroger:build (plus kroger:enrich if --zipcode is set)
  --stages=a,b,c         Pick specific stages by name, comma separated
  --zipcode=XXXXX        Zip code required for kroger:enrich
  --stores=N             Max stores for kroger:enrich (default: 10, or "all")
  --radius=N             Store search radius in miles (default: 25)
  --dry-run              Small batches, safe for testing
  --llm                  Enable Ollama LLM in walmart:classify (default: rules-only)
  --model=NAME           Ollama model (default: llama3.2:1b)
  --workers=N            Parallel LLM workers (default: 8)
  --supabase             Run supabase:walmart and supabase:kroger
  --continue-on-error    Keep going after a stage fails instead of stopping
  --help, -h             Show this help text

Stages (in order):
${stageList}

Examples:
  node runner.js --all
  node runner.js --walmart
  node runner.js --kroger --zipcode=90210
  node runner.js --all --dry-run
  node runner.js --stages=walmart:fetch,kroger:build
  node runner.js --walmart --llm --model=llama3.2:3b
`);
}

async function main() {
  if (showHelp) {
    printHelp();
    return;
  }

  const stages = selectStages();

  if (!stages.length) {
    console.error(
      'No stages selected. Use --all, --walmart, --kroger, --stages=..., or --help.',
    );
    process.exit(1);
  }

  const divider = '-'.repeat(60);
  const divider2 = '='.repeat(60);

  console.log(`\nShopwise Pipeline Runner`);
  console.log(divider2);
  console.log(`Stages to run (${stages.length}):`);
  stages.forEach((s, i) => console.log(`  ${i + 1}. [${s.id}] ${s.label}`));
  if (isDryRun) console.log('\n  DRY RUN - small batches only');

  const results = [];
  const t0 = Date.now();

  for (const stage of stages) {
    console.log(`\n${divider}`);
    console.log(`[${stage.id}] ${stage.label}`);
    console.log(divider);

    const ts = Date.now();
    try {
      await stage.run();
      const elapsed = formatElapsed(ts);
      console.log(`\n[${stage.id}] done in ${elapsed}`);
      results.push({ id: stage.id, ok: true, elapsed });
    } catch (err) {
      const elapsed = formatElapsed(ts);
      console.error(`\n[${stage.id}] FAILED: ${err.message}`);
      results.push({ id: stage.id, ok: false, elapsed, error: err.message });
      if (!continueErr) {
        console.error(
          `\nStopped. Run with --continue-on-error to keep going after failures.`,
        );
        break;
      }
    }
  }

  const total = formatElapsed(t0);
  const failed = results.filter((r) => !r.ok);

  console.log(`\n${divider2}`);
  console.log(
    `Done in ${total}  |  ${results.length - failed.length}/${results.length} stages passed`,
  );
  console.log(divider2);
  results.forEach((r) => {
    const status = r.ok ? '[ok]  ' : '[FAIL]';
    const note = r.error ? ` - ${r.error}` : '';
    console.log(`  ${status} [${r.id}] (${r.elapsed})${note}`);
  });
  console.log('');

  if (failed.length) process.exit(1);
}

function formatElapsed(startTime) {
  const ms = Date.now() - startTime;
  return ms < 60_000
    ? `${(ms / 1000).toFixed(1)}s`
    : `${Math.floor(ms / 60000)}m ${Math.floor((ms % 60000) / 1000)}s`;
}

main().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
