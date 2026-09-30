// SPDX-License-Identifier: MPL-2.0
// Original packaging utility. Covered module output retains source notices.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
const read = file => fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
function modulesAt(dir, prefix = '') {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(entry => {
    const rel = path.posix.join(prefix, entry.name);
    return entry.isDirectory() ? modulesAt(path.join(dir, entry.name), rel) : entry.name.endsWith('.luau') ? [rel] : [];
  }).sort();
}
export function rewriteImports(source, modulePath, modulePaths) {
  const known = new Set(modulePaths);
  function reference(dependency) {
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(modulePath), dependency)).replace(/\.luau$/, '') + '.luau';
    if (target.startsWith('../') || !known.has(target)) throw new Error(`Unknown/outside module import in ${modulePath}: ${dependency}`);
    const fromParts = path.posix.dirname(modulePath).split('/').filter(v => v !== '.');
    const toParts = target.replace(/\.luau$/, '').split('/');
    let common = 0;
    while (common < fromParts.length && common < toParts.length - 1 && fromParts[common] === toParts[common]) common++;
    let expression = 'script.Parent' + '.Parent'.repeat(fromParts.length - common);
    for (const part of toParts.slice(common)) {
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
      const end = longEnd(index + 2) ?? (source.indexOf('\n', index) < 0 ? source.length : source.indexOf('\n', index));
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
      output += source.slice(index, end); index = end; continue;
    }
    const long = character === '[' ? longEnd(index) : null;
    if (long !== null) {output += source.slice(index, long); index = long; continue;}
    if (source.startsWith('require', index) && (index === 0 || !/[\w.:]/.test(source[index - 1]))) {
      const call = source.slice(index).match(/^require\(\s*(['"])(\.[^'"\n]*)\1\s*\)/);
      if (call) {output += reference(call[2]); index += call[0].length; continue;}
    }
    output += character; index++;
  }
  return output;
}
export function exportModules({check = false} = {}) {
  const sourceRoot = path.join(root, 'src');
  const outputRoot = path.join(root, 'roblox');
  const modulePaths = modulesAt(sourceRoot);
  if (!modulePaths.length) throw new Error('No converted source modules');
  const lock = JSON.parse(read(path.join(root, 'upstream.lock.json')));
  const manifest = {formatVersion: 1, upstreamRevision: lock.revision, modules: []};
  const outputs = new Map();
  for (const modulePath of modulePaths) {
    const source = read(path.join(sourceRoot, modulePath));
    const sourceSha256 = hash(source);
    const generated = `-- Generated module-only Roblox form. Source: src/${modulePath}\n-- Source SHA-256: ${sourceSha256}\n-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.\n` + rewriteImports(source, modulePath, modulePaths).replace(/\n+$/, '\n');
    outputs.set(modulePath, generated);
    manifest.modules.push({path: `roblox/${modulePath}`, sourcePath: `src/${modulePath}`, sourceSha256, generatedSha256: hash(generated)});
  }
  outputs.set('manifest.json', JSON.stringify(manifest, null, 2) + '\n');
  if (check) {
    if (!fs.existsSync(outputRoot)) throw new Error('Missing generated roblox/ modules');
    const actual = modulesAt(outputRoot);
    if (JSON.stringify(actual) !== JSON.stringify(modulePaths)) throw new Error('Generated module set differs from src/');
    for (const [rel, expected] of outputs) {
      const file = path.join(outputRoot, rel);
      if (!fs.existsSync(file) || read(file) !== expected) throw new Error(`Stale generated file: roblox/${rel}`);
    }
    console.log(`Roblox module export reproducible (${modulePaths.length} modules)`);
  } else {
    if (fs.existsSync(outputRoot)) {
      const stale = modulesAt(outputRoot).filter(p => !modulePaths.includes(p));
      if (stale.length) throw new Error(`Stale generated modules require explicit review/removal: ${stale.join(', ')}`);
    }
    for (const [rel, contents] of outputs) {
      const file = path.join(outputRoot, rel);
      fs.mkdirSync(path.dirname(file), {recursive: true});
      fs.writeFileSync(file, contents);
    }
    console.log(`Exported ${modulePaths.length} MPL-covered Roblox modules; no game entrypoint`);
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { exportModules({check: process.argv.includes('--check')}); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
