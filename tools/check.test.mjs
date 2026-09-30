// SPDX-License-Identifier: MPL-2.0
// Meaningful regression checks for the public metadata gate using disposable fixtures.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const check=path.join(path.dirname(fileURLToPath(import.meta.url)),'check.mjs');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-luau-gates-'));
const revision='42939c6a2cf31aa76f44ffc033015ad12fece9f5';
const write=(p,t)=>{fs.mkdirSync(path.dirname(path.join(temp,p)),{recursive:true});fs.writeFileSync(path.join(temp,p),t);};
const run=()=>spawnSync(process.execPath,[check,'verify'],{cwd:temp,encoding:'utf8'});
try{
  write('LICENSE','Fixture only');write('ATTRIBUTIONS.md','Fixture only');
  write('upstream.lock.json',JSON.stringify({revision}));
  write('provenance/inventory.json',JSON.stringify({revision,summary:{total:1},files:[{path:'core/src/com/unciv/models/Counter.kt',disposition:'convert',reason:'gameplay',risk:'numbers',implementationStatus:'not-converted'}]}));
  write('provenance/fixture.json',JSON.stringify({modules:[{path:'src/Counter.luau',license:'MPL-2.0'}]}));
  const valid=`--!strict\n-- SPDX-License-Identifier: MPL-2.0\n-- Upstream: core/src/com/unciv/models/Counter.kt @ ${revision}\nreturn {}\n`;
  write('src/Counter.luau',valid);write('tests/unit/counter.luau','-- SPDX-License-Identifier: MPL-2.0\nassert(true)\n');
  assert.equal(run().status,0,'Valid public metadata must pass');
  write('src/Counter.luau',valid.replace('SPDX-License-Identifier: MPL-2.0','missing licence'));
  let result=run();assert.notEqual(result.status,0);assert.match(result.stderr,/missing MPL SPDX/);
  write('src/Counter.luau',valid+'local service = game:GetService("Players")\n');
  result=run();assert.notEqual(result.status,0);assert.match(result.stderr,/Roblox host global/);
  write('src/Counter.luau',valid);write('provenance/fixture.json','{}');
  result=run();assert.notEqual(result.status,0);assert.match(result.stderr,/no source provenance record/);
  console.log('Metadata gate regression checks passed (valid metadata, missing licence, host globals, absent provenance).');
}finally{fs.rmSync(temp,{recursive:true,force:true});}
