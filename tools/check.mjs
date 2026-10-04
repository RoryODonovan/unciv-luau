// SPDX-License-Identifier: MPL-2.0
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.cwd();
const files=(dir)=>fs.existsSync(dir)?fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name)):[path.join(dir,e.name)]):[];
const mode=process.argv[2]??'all';
if(!['all','verify','test','analyze'].includes(mode)) throw new Error('Expected all, verify, test or analyze');
let errors=[];
const assert=(ok,msg)=>{if(!ok)errors.push(msg);};
const modules=files('src').filter(p=>p.endsWith('.luau'));
const tests=files('tests/unit').filter(p=>p.endsWith('.luau'));
// Golden tests use a Node adapter for baseline JSON I/O, unavailable in the standalone Luau CLI.
const golden=files('tests/golden').filter(p=>p.endsWith('.luau'));
const goldenRunner=path.join('tests','golden','run.mjs');
const normalize=p=>p.replaceAll('\\','/');
const provenance=files('provenance').filter(p=>p.endsWith('.json')&&!p.endsWith('inventory.json'));
function run(binary,args){const result=spawnSync(binary,args,{cwd:root,stdio:'inherit'});if(result.error)throw result.error;if(result.status!==0)throw new Error(`${binary} failed with status ${result.status}`);}
if(mode==='all'||mode==='verify'){
  for(const p of ['LICENSE','ATTRIBUTIONS.md','upstream.lock.json','provenance/inventory.json'])assert(fs.existsSync(p),`Missing ${p}`);
  let lock;
  try{lock=JSON.parse(fs.readFileSync('upstream.lock.json','utf8').replace(/^\uFEFF/,''));assert(/^[a-f0-9]{40}$/.test(lock.revision),'upstream.lock.json needs full revision');}catch(e){errors.push(`Invalid upstream.lock.json: ${e.message}`);}
  let manifestTexts=[], manifestRecords=[];
  for(const p of provenance){try{const raw=fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'');manifestRecords.push(JSON.parse(raw));manifestTexts.push(raw.replaceAll('\\\\','/'));}catch(e){errors.push(`Invalid ${p}: ${e.message}`);}}
  const inventory=JSON.parse(fs.readFileSync('provenance/inventory.json','utf8').replace(/^\uFEFF/,''));
  assert(inventory.revision===lock?.revision,'Inventory revision differs from upstream lock');
  assert(inventory.files?.length===inventory.summary?.total,'Inventory count mismatch');
  for(const entry of inventory.files??[]){assert(['convert','defer','exclude'].includes(entry.disposition)&&entry.reason&&entry.risk,`Missing inventory classification: ${entry.path}`);assert(entry.implementationStatus==='not-converted',`Inventory baseline must not imply implementation: ${entry.path}`);}
  assert(modules.length>0,'No converted modules found');assert(tests.length>0,'No unit tests found');
  for(const p of [...modules,...tests,...golden]){
    const text=fs.readFileSync(p,'utf8');const header=text.slice(0,2000);
    assert(header.includes('SPDX-License-Identifier: MPL-2.0'),`${p}: missing MPL SPDX notice`);
    if(modules.includes(p)){
      assert(header.includes('--!strict'), `${p}: public module must use strict types`);
      const original = header.includes('-- Provenance-Kind: original');
      if (original) {
        assert(manifestRecords.some(record => record.provenanceKind === 'original' && record.license === 'MPL-2.0' && record.modulePaths?.includes(normalize(p))), `${p}: original module needs explicit original MPL provenance`);
      } else {
        assert(/core\/src\/com\/unciv\/[^\s]+\.kt/.test(header),`${p}: missing upstream Kotlin source path`);
        assert(header.includes(lock?.revision),`${p}: missing pinned revision`);
      }
      assert(manifestTexts.some(t=>t.includes(normalize(p))),`${p}: no source provenance record`);
      // Strip comments/strings before checking actual host-global references, avoiding false positives in notices.
      const code=text.replace(/--\[\[[\s\S]*?\]\]|--[^\n]*/g,'').replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g,'');
      assert(!/\b(game|workspace|Instance)\s*[.:\[(]/.test(code),`${p}: Roblox host global in public module`);
      assert(!/\b(GetService|HttpService|DataStoreService|Players|ReplicatedStorage)\b/.test(code),`${p}: Roblox service reference in public module`);
    }
  }
  // Checked-in assets require an explicit per-file licence decision; inventory entries are not permissions.
  for(const p of files('assets'))assert(manifestTexts.some(t=>t.includes(normalize(p))&&t.includes('license')),`${p}: asset has no explicit licence/provenance record`);
  const tracked=spawnSync('git',['ls-files'],{encoding:'utf8'});if(tracked.status===0)for(const p of tracked.stdout.split(/\r?\n/).filter(Boolean))assert(!/(^|\/)(\.env(?:\..*)?|private|credentials|secrets)(\/|$)|\.(rbxl|rbxlx)$/i.test(p),`Forbidden private/game file tracked: ${p}`);
  if(errors.length)throw new Error(errors.join('\n'));
  console.log(`Verified ${modules.length} modules, ${tests.length} test files and ${inventory.files.length} inventory entries.`);
}
if(mode==='all'||mode==='analyze'){
  assert(modules.length>0,'No modules for analysis');if(errors.length)throw new Error(errors.join('\n'));
  run(process.env.LUAU_ANALYZE_BIN??'luau-analyze',[...modules,...tests,...golden]);
}
if(mode==='all'||mode==='test'){
  if(!tests.length)throw new Error('No unit tests found');
  for(const p of tests.sort())run(process.env.LUAU_BIN??'luau',[p]);
  if(fs.existsSync(goldenRunner))run(process.execPath,[goldenRunner]);
  console.log(`Passed ${tests.length} standalone test files.`);
}

