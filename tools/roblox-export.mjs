// SPDX-License-Identifier: MPL-2.0
// Original packaging utility. Covered module output retains source notices.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
const read = file => fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
function filesAt(dir, prefix = '') {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(entry => {
    const relative = path.posix.join(prefix, entry.name);
    return entry.isDirectory() ? filesAt(path.join(dir, entry.name), relative) : [relative];
  }).sort();
}
export function rewriteImports(source, modulePath, modulePaths) {
  const known = new Set(modulePaths);
  const reserved = new Set(['Name', 'Parent', 'ClassName', 'Archivable', 'Source', 'Disabled', 'Enabled', 'RunContext', 'UniqueId', 'LinkedSource', 'Sandboxed', 'Capabilities']);
  function reference(dependency) {
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(modulePath), dependency)).replace(/\.luau$/, '') + '.luau';
    if (target.startsWith('../') || !known.has(target)) throw new Error(`Unknown/outside module import in ${modulePath}: ${dependency}`);
    const fromParts = path.posix.dirname(modulePath).split('/').filter(v => v !== '.');
    const toParts = target.replace(/\.luau$/, '').split('/');
    let common = 0;
    while (common < fromParts.length && common < toParts.length - 1 && fromParts[common] === toParts[common]) common++;
    let expression = 'script.Parent' + '.Parent'.repeat(fromParts.length - common);
    for (const part of toParts.slice(common)) {
      if (reserved.has(part)) throw new Error(`Reserved Roblox child name: ${part}`);
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(part)) throw new Error(`Unsupported ModuleScript name: ${part}`);
      expression += `.${part}`;
    }
    return `require(${expression})`;
  }
  function longEnd(index) {
    const opening = source.slice(index).match(/^\[(=*)\[/);
    if (!opening) return null;
    const closing = `]${opening[1]}]`;
    const end = source.indexOf(closing, index + opening[0].length);
    if (end < 0) throw new Error(`Unterminated long string/comment in ${modulePath}`);
    return end + closing.length;
  }
  let output = '', index = 0;
  while (index < source.length) {
    if (source.startsWith('--', index)) {
      const newline = source.indexOf('\n', index);
      const end = longEnd(index + 2) ?? (newline < 0 ? source.length : newline);
      output += source.slice(index, end); index = end; continue;
    }
    const character = source[index];
    if (character === '"' || character === "'" || character === '`') {
      let end = index + 1;
      while (end < source.length) {
        if (source[end] === '\\') {end += 2; continue;}
        if (source[end] === character) {end++; break;}
        end++;
      }
      if (character === '`' && /(?<!\\)\{/.test(source.slice(index, end))) throw new Error(`Interpolated strings are unsupported in module export: ${modulePath}`);
      output += source.slice(index, end); index = end; continue;
    }
    const long = character === '[' ? longEnd(index) : null;
    if (long !== null) {output += source.slice(index, long); index = long; continue;}
    if (source.startsWith('require', index) && !/\w/.test(source[index + 7] ?? '') && (index === 0 || !/[\w.:]/.test(source[index - 1]))) {
      const call = source.slice(index).match(/^require\s*\(\s*(['"])(\.[^'"\n]*)\1\s*\)/);
      if (call) {output += reference(call[2]); index += call[0].length; continue;}
      throw new Error(`Unsupported require form in ${modulePath}; use a direct relative string import`);
    }
    output += character; index++;
  }
  return output;
}
export function exportModules({check = false} = {}) {
  const sourceRoot = path.join(root, 'src');
  const outputRoot = path.join(root, 'roblox');
  const modulePaths = filesAt(sourceRoot).filter(relative => relative.endsWith('.luau'));
  if (!modulePaths.length) throw new Error('No converted source modules');
  for (const modulePath of modulePaths) if (/(^|\/)init\.luau$|\.(server|client)\.luau$/.test(modulePath)) throw new Error(`Unsupported Rojo module shape: ${modulePath}`);
  const lock = JSON.parse(read(path.join(root, 'upstream.lock.json')));
  const manifest = {formatVersion: 1, upstreamRevision: lock.revision, modules: []};
  const outputs = new Map();
  for (const modulePath of modulePaths) {
    const source = read(path.join(sourceRoot, modulePath));
    const sourceSha256 = hash(source);
    const header = `--!strict\n-- Generated module-only Roblox form. Source: src/${modulePath}\n-- Source SHA-256: ${sourceSha256}\n-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.\n-- Covered source: https://github.com/RoryODonovan/unciv-luau\n-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.\n-- Obtain a copy at https://mozilla.org/MPL/2.0/.\n`;
    const generated = header + rewriteImports(source, modulePath, modulePaths).replace(/\n+$/, '\n');
    outputs.set(modulePath, generated);
    manifest.modules.push({path: `roblox/${modulePath}`, sourcePath: `src/${modulePath}`, sourceSha256, generatedSha256: hash(generated)});
  }
  outputs.set('manifest.json', JSON.stringify(manifest, null, 2) + '\n');
  if (fs.existsSync(outputRoot)) {
    const unexpected = filesAt(outputRoot).filter(relative => !outputs.has(relative));
    if (unexpected.length) throw new Error(`Unexpected generated files require explicit review/removal: ${unexpected.join(', ')}`);
  }
  if (check) {
    if (!fs.existsSync(outputRoot)) throw new Error('Missing generated roblox/ modules');
    for (const [relative, expected] of outputs) {
      const file = path.join(outputRoot, relative);
      if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== expected) throw new Error(`Stale/noncanonical generated file: roblox/${relative}`);
    }
    console.log(`Roblox module export reproducible (${modulePaths.length} modules)`);
  } else {
    for (const [relative, contents] of outputs) {
      const file = path.join(outputRoot, relative);
      fs.mkdirSync(path.dirname(file), {recursive: true});
      fs.writeFileSync(file, contents);
    }
    console.log(`Exported ${modulePaths.length} MPL-covered Roblox modules; no game entrypoint`);
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {exportModules({check: process.argv.includes('--check')});}
  catch (error) {console.error(error.message); process.exitCode = 1;}
}
