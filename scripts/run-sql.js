#!/usr/bin/env node
'use strict';

// Load environment variables from .env if present
try { require('dotenv').config(); } catch (_) {}

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const toml = require('toml');

function fail(msg) {
  console.error(`[run-sql] ERROR: ${msg}`);
  process.exit(1);
}

function usageAndExit() {
  console.log('Usage: node scripts/run-sql.js [<path-to-sql>] [-e "<inline-sql>"] [--remote]');
  console.log('Notes:');
  console.log('  - Provide either a SQL file OR -e/--execute (mutually exclusive).');
  console.log('  - If neither is provided, defaults to docs/sql/stage2-verify.sql.');
  console.log('  - --remote is a compatibility flag; connection is determined by env (SUPABASE_DB_URL or project_id+SUPABASE_DB_PASSWORD).');
  console.log('Connection resolution (priority):');
  console.log('  1) SUPABASE_DB_URL (sslmode=require will be appended if missing)');
  console.log('  2) project_id from supabase/config.toml + SUPABASE_DB_PASSWORD');
  process.exit(2);
}

function readProjectIdFromToml(tomlPath = path.join(process.cwd(), 'supabase', 'config.toml')) {
  try {
    const raw = fs.readFileSync(tomlPath, 'utf8');
    const parsed = toml.parse(raw);
    if (parsed && typeof parsed.project_id === 'string' && parsed.project_id.trim()) {
      return parsed.project_id.trim();
    }
    return null;
  } catch (_e) {
    return null;
  }
}

function ensureSslmodeRequire(urlStr) {
  try {
    const u = new URL(urlStr);
    // Only append if not present
    if (!u.searchParams.has('sslmode')) {
      u.searchParams.set('sslmode', 'require');
    }
    return u.toString();
  } catch (e) {
    // If URL parsing fails, fall back to naive append if not already has ? or &
    if (!/[?&]sslmode=/.test(urlStr)) {
      return urlStr + (urlStr.includes('?') ? '&' : '?') + 'sslmode=require';
    }
    return urlStr;
  }
}

function buildDirectUrl(projectId, password) {
  const pw = encodeURIComponent(password);
  return `postgresql://postgres:${pw}@db.${projectId}.supabase.co:5432/postgres?sslmode=require`;
}

function resolveConnectionString() {
  const envUrl = (process.env.SUPABASE_DB_URL || '').trim();
  if (envUrl) {
    return ensureSslmodeRequire(envUrl);
  }

  const projectId = readProjectIdFromToml();
  if (!projectId) {
    fail('Missing project_id in supabase/config.toml. Link the repo with "yarn supa:link" or provide SUPABASE_DB_URL.');
  }
  const password = (process.env.SUPABASE_DB_PASSWORD || '').trim();
  if (!password) {
    fail('Missing SUPABASE_DB_PASSWORD. Set it or provide SUPABASE_DB_URL instead. Do not commit secrets.');
  }
  return buildDirectUrl(projectId, password);
}

function parseArgs(argv) {
  let fileArg = null;
  let inlineSql = null;
  let remote = false; // compatibility flag; connection determined by env
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '-h' || a === '--help') {
      usageAndExit();
    } else if (a === '-e' || a === '--execute') {
      if (inlineSql !== null) fail('Duplicate -e/--execute provided.');
      if (i + 1 >= argv.length) fail('Expected SQL string after -e/--execute.');
      inlineSql = argv[++i];
    } else if (a.startsWith('-e=')) {
      if (inlineSql !== null) fail('Duplicate -e/--execute provided.');
      inlineSql = a.substring(3);
    } else if (a.startsWith('--execute=')) {
      if (inlineSql !== null) fail('Duplicate -e/--execute provided.');
      inlineSql = a.substring('--execute='.length);
    } else if (a === '-r' || a === '--remote') {
      remote = true;
    } else if (a.startsWith('-')) {
      fail(`Unknown option: ${a}`);
    } else {
      if (fileArg !== null) fail('Only one SQL file argument is allowed.');
      fileArg = a;
    }
  }
  if (fileArg && inlineSql) {
    fail('Provide either a SQL file OR -e/--execute, not both.');
  }
  if (!fileArg && !inlineSql) {
    fileArg = path.join('docs', 'sql', 'stage2-verify.sql');
  }
  return { fileArg, inlineSql, remote };
}

function readSql({ fileArg, inlineSql }) {
  if (inlineSql && inlineSql.trim()) {
    return { sql: inlineSql, source: '(inline)' };
  }
  const absolute = path.isAbsolute(fileArg) ? fileArg : path.join(process.cwd(), fileArg);
  if (!fs.existsSync(absolute)) {
    fail(`SQL file not found: ${absolute}`);
  }
  const sql = fs.readFileSync(absolute, 'utf8');
  return { sql, source: absolute };
}

function formatValue(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

function printTable(rows) {
  if (!Array.isArray(rows) || rows.length === 0) {
    console.log('[run-sql] (no rows)');
    return;
  }
  const cols = Array.from(new Set(rows.flatMap(r => Object.keys(r))));
  const widths = cols.map(c => Math.max(c.length, ...rows.map(r => formatValue(r[c]).length)));
  const divider = '+' + widths.map(w => '-'.repeat(w + 2)).join('+') + '+';
  const header = '|' + cols.map((c, i) => ' ' + c.padEnd(widths[i]) + ' ').join('|') + '|';
  console.log(divider);
  console.log(header);
  console.log(divider);
  for (const r of rows) {
    const line = '|' + cols.map((c, i) => ' ' + formatValue(r[c]).padEnd(widths[i]) + ' ').join('|') + '|';
    console.log(line);
  }
  console.log(divider);
}

async function main() {
  const { fileArg, inlineSql } = parseArgs(process.argv.slice(2));
  const { sql, source } = readSql({ fileArg, inlineSql });

  const connectionString = resolveConnectionString();
  const client = new Client({
    connectionString,
    statement_timeout: 60_000
  });

  const started = Date.now();
  console.log(`[run-sql] Connecting using resolved connection string...`);
  await client.connect();
  console.log(`[run-sql] Connected. Executing: ${source}`);

  try {
    const res = await client.query(sql);
    const rows = Array.isArray(res.rows) ? res.rows : [];
    if (rows.length > 0) {
      // If result has the verification shape, print a friendly condensed table
      const looksLikeVerify = Object.prototype.hasOwnProperty.call(rows[0] || {}, 'label');
      if (looksLikeVerify) {
        console.log('label | pass | matches | rows | details');
        for (const row of rows) {
          const pass = row.pass === null || row.pass === undefined ? '' : (row.pass ? 'PASS' : 'FAIL');
          console.log(`${row.label} | ${pass} | ${row.matches ?? ''} | ${row.rows ?? ''} | ${row.details ?? ''}`);
        }
      } else {
        printTable(rows);
      }
    } else {
      console.log('[run-sql] Query executed (no rows).');
    }
    await client.end();
    console.log(`[run-sql] Completed in ${Math.round((Date.now() - started) / 1000)}s`);
    process.exit(0);
  } catch (err) {
    console.error('[run-sql] Query error:', err?.message || err);
    try { await client.end(); } catch {}
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('[run-sql] Uncaught error:', err?.message || err);
  process.exit(1);
});