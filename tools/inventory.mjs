// SPDX-License-Identifier: MPL-2.0
// Inventory metadata only: no upstream implementation or assets are copied.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
const revision = '42939c6a2cf31aa76f44ffc033015ad12fece9f5';
const upstream = path.resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw new Error('Usage: node tools/inventory.mjs <pinned Unciv checkout>');
const git = (...args) => execFileSync('git', ['-C', upstream, ...args], {encoding:'utf8'}).trim();
if (git('rev-parse','HEAD') !== revision) throw new Error('Upstream HEAD differs from pinned revision');
const roots = ['core/src', 'tests', 'android/assets/jsons'];
if (git('status', '--porcelain', '--', ...roots)) throw new Error('Scoped upstream files must be clean');
const files = git('ls-files', ...roots).split('\n').filter(Boolean).sort();
const texts = new Map(files.map(p => [p, fs.readFileSync(path.join(upstream,p),'utf8')]));
const sourceFiles = files.filter(p => p.endsWith('.kt'));
const packages = new Map();
const symbols = new Map();
for (const p of sourceFiles) {
  const t = texts.get(p);
  const pkg = /^package\s+([\w.]+)/m.exec(t)?.[1];
  if (!pkg) continue;
  if (!packages.has(pkg)) packages.set(pkg,[]);
  packages.get(pkg).push(p);
  // Resolve explicit class/object/typealias names. Top-level functions may be extensions;
  // ambiguous symbol names remain recorded with all candidates.
  for (const m of t.matchAll(/^(?:(?:public|internal|private|protected|open|abstract|data|enum|sealed|value|inline|suspend|override)\s+)*(?:class|interface|object|typealias|fun|val|var)\s+(?:<[^>]+>\s*)?(\w+)/gm)) {
    const key = `${pkg}.${m[1]}`;
    if (!symbols.has(key)) symbols.set(key, []);
    symbols.get(key).push(p);
  }
  const basename = path.basename(p,'.kt');
  const key = `${pkg}.${basename}`;
  if (!symbols.has(key)) symbols.set(key,[p]);
}
function classify(p) {
  if (p.startsWith('android/assets/jsons/')) return {disposition:'defer',subsystem:p.includes('/translations/')?'localization-data':p.includes('/TileSets/')?'render-data':'rules-data',reason:'Do not import until this individual file has a verified licence and attribution audit; repository code licence is not sufficient evidence for assets.',risk:'licence/provenance audit required',licenseStatus:'unverified-not-imported'};
  if (p.startsWith('tests/')) return {disposition:p.endsWith('.kt')?'defer':'exclude',subsystem:'upstream-test-reference',reason:p.endsWith('.kt')?'Use as behavioural reference after the corresponding modules exist; JVM fixtures and framework require replacement.':'JVM build configuration is not a Luau runtime dependency.',risk:'test fixture and platform dependencies',licenseStatus:'MPL-2.0-code-reference'};
  const rel=p.replace('core/src/com/unciv/','');
  if (/^(ui|view)\//.test(rel)||/^(GUI|UncivGame|PlatformSpecific)\.kt$/.test(rel)||/^models\/(skins|tilesets|objectdescriptions)\//.test(rel)||/^models\/(ImmutableColor|UncivSound|TutorialTrigger)\.kt$/.test(rel)) return {disposition:'exclude',subsystem:'presentation',reason:'Desktop/mobile rendering, immutable view API, UI metadata or platform entrypoint is replaced by private Roblox presentation.',risk:'LibGDX/UI coupling',licenseStatus:'MPL-2.0-code-reference'};
  if (/^logic\/(multiplayer|files|github|audio|crashhandling|event)\//.test(rel)||/^utils\/(Concurrency|Log|DebugUtils|Display|HolidayDates|IdChecker)\.kt$/.test(rel)||/^logic\/(UncivKtor|Versioning|AlternatingStateManager|HolidayDates|IdChecker)\.kt$/.test(rel)) return {disposition:'exclude',subsystem:'platform-services',reason:'JVM networking, storage, concurrency, diagnostics or application lifecycle is replaced by integration contracts.',risk:'host and service dependencies',licenseStatus:'MPL-2.0-code-reference'};
  if (/^models\/translations\//.test(rel)||/^json\//.test(rel)||/^models\/metadata\//.test(rel)||/^logic\/(BackwardCompatibility|GameStarter)\.kt$/.test(rel)) return {disposition:'defer',subsystem:'serialization-localization-setup',reason:'Define platform-neutral data and host contracts before deciding whether to port; save compatibility and translations are not initially supported.',risk:'serialization, locale and setup coupling',licenseStatus:'MPL-2.0-code-reference'};
  const match=/^(?:logic|models)\/([^/]+)\//.exec(rel);
  const subsystem=match?.[1] ?? (/^(utils|models)\//.test(rel)?'foundation':'simulation');
  const high=['ruleset','automation','civilization','battle','city','map','simulation','trade'].includes(subsystem);
  return {disposition:'convert',subsystem,reason:'Planned reusable gameplay or supporting model conversion; separate host/UI imports behind contracts and verify behaviour before marking implemented.',risk:high?'state, rules effects, order and numeric parity':'collection, numeric or dependency semantics',licenseStatus:'MPL-2.0-code-reference'};
}
const entries=files.map(p=>{
  const t=texts.get(p);
  const imports=[...t.matchAll(/^import\s+([\w.*]+)(?:\s+as\s+(\w+))?/gm)].map(m=>{
    const name=m[1];
    let targets=name.endsWith('.*') ? packages.get(name.slice(0,-2)) ?? [] : symbols.get(name) ?? [];
    if (!targets.length && !name.endsWith('.*')) {
      let prefix=name;
      while (prefix.includes('.') && !targets.length) {prefix=prefix.slice(0,prefix.lastIndexOf('.'));targets=symbols.get(prefix)??[];}
    }
    return {name,...(m[2]?{alias:m[2]}:{}),resolution:targets.length?(name.endsWith('.*')?'wildcard-package-candidates':'symbol-candidates'):name.startsWith('com.unciv.')?'unresolved-internal':'external',targets:[...new Set(targets)].sort()};
  });
  return {path:p,sha256:crypto.createHash('sha256').update(t).digest('hex'),bytes:Buffer.byteLength(t),...classify(p),implementationStatus:'not-converted',imports,internalDependencyCandidates:[...new Set(imports.flatMap(i=>i.targets).filter(q=>q!==p))].sort()};
});
const counts=key=>Object.fromEntries([...new Set(entries.map(e=>e[key]))].sort().map(k=>[k,entries.filter(e=>e[key]===k).length]));
const output={schemaVersion:1,repository:'https://github.com/yairm210/Unciv',revision,scope:roots,method:'Tracked files in pinned sparse checkout; textual Kotlin imports resolved to package/symbol candidates, not a compiler call graph. No assets copied. All implementation statuses describe inventory baseline, not current conversion progress.',summary:{total:entries.length,disposition:counts('disposition'),subsystem:counts('subsystem'),importDeclarations:entries.reduce((n,e)=>n+e.imports.length,0),internalCandidateEdges:entries.reduce((n,e)=>n+e.internalDependencyCandidates.length,0),unresolvedInternalImports:entries.reduce((n,e)=>n+e.imports.filter(i=>i.resolution==='unresolved-internal').length,0)},files:entries};
fs.writeFileSync('provenance/inventory.json',JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify(output.summary,null,2));

