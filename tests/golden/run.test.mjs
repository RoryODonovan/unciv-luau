// SPDX-License-Identifier: MPL-2.0
// Adapter protocol tests use a disposable fake CLI; actual engine/save parity runs in replay-corpus.luau.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';

test('baseline adapter compares subset/full, reports fog and metadata drift, and protects updates',()=>{
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-golden-adapter-'));
  const directory=path.join(temporary,'tests/golden');
  fs.mkdirSync(directory,{recursive:true});
  const baselinePath=path.join(directory,'baseline.json');
  try {
    fs.copyFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)),'run.mjs'),path.join(directory,'run.mjs'));
    const config={presets:[{name:'Quick'},{name:'Standard'},{name:'Full'}],shapes:['Hex','Sphere'],seeds:[1,2,3,4,5,6,7,8],defaultSeedCount:2};
    const games=config.presets.flatMap(p=>config.shapes.flatMap(shape=>config.seeds.map((seed,index)=>({
      id:`${p.name}/${shape}/seed-${seed}/barbarians-${index%2===0?'on':'off'}`,
      finalRound:20,phase:'Finished',winner:2,victoryType:'Score',
      checkpoints:[{checkpoint:'final',hashes:{state:'1111111111111111',actor1:'2222222222222222',actor2:'3333333333333333'}}],
    }))));
    const corpus={config,games};
    const original=JSON.stringify(corpus,null,2)+'\n';
    fs.writeFileSync(baselinePath,original);
    fs.writeFileSync(path.join(directory,'fixture.json'),JSON.stringify(corpus));
    // Node accepts a plain JS main script with a .luau suffix when no package.json declares an ESM scope.
    fs.writeFileSync(path.join(directory,'replay-corpus.luau'),`
      const fs=require('node:fs');
      const c=JSON.parse(fs.readFileSync(__dirname+'/fixture.json','utf8'));
      console.log('GOLDEN_CONFIG '+JSON.stringify(c.config));
      const selected=process.argv.at(-1)==='full'?c.games:c.games.filter((g,i)=>i%8<2);
      for(const g of selected)console.log('GOLDEN_GAME '+JSON.stringify(g));
    `);
    const run=(env={})=>spawnSync(process.execPath,[path.join(directory,'run.mjs')],{
      encoding:'utf8',env:{...process.env,LUAU_BIN:process.execPath,GOLDEN_FULL:'',GOLDEN_UPDATE:'',...env},
    });
    let result=run(); assert.equal(result.status,0,result.stderr); assert.match(result.stdout,/default: 12 games passed/);
    result=run({GOLDEN_FULL:'1'}); assert.equal(result.status,0,result.stderr); assert.match(result.stdout,/full: 48 games passed/);
    const changed=structuredClone(corpus); changed.games[0].checkpoints[0].hashes.actor2='4444444444444444';
    fs.writeFileSync(baselinePath,JSON.stringify(changed));
    result=run(); assert.equal(result.status,1); assert.match(result.stderr,/GOLDEN MISMATCH Quick\/Hex\/seed-1\/barbarians-on\.checkpoints\[final\]\.hashes\.actor2: expected "4444444444444444", actual "3333333333333333"/);
    changed.games[0].checkpoints=corpus.games[0].checkpoints; changed.games[0].finalRound=21;
    fs.writeFileSync(baselinePath,JSON.stringify(changed));
    result=run(); assert.equal(result.status,1); assert.match(result.stderr,/finalRound: expected 21, actual 20/);
    result=run({GOLDEN_UPDATE:'1'}); assert.equal(result.status,0,result.stderr); assert.match(result.stderr,/WARNING: GOLDEN_UPDATE=1/);
    assert.equal(fs.readFileSync(baselinePath,'utf8'),original,'update must record all 48 games even without GOLDEN_FULL');
    fs.writeFileSync(path.join(directory,'fixture.json'),JSON.stringify({...corpus,games:games.slice(0,1)}));
    result=run({GOLDEN_UPDATE:'1'}); assert.equal(result.status,1); assert.match(result.stderr,/Incomplete golden corpus/);
    assert.equal(fs.readFileSync(baselinePath,'utf8'),original,'incomplete update must preserve the committed baseline');
    fs.writeFileSync(path.join(directory,'replay-corpus.luau'),'process.exit(7)');
    result=run({GOLDEN_UPDATE:'1'}); assert.equal(result.status,1); assert.match(result.stderr,/status 7/);
    assert.equal(fs.readFileSync(baselinePath,'utf8'),original,'CLI failure must preserve the committed baseline');
    console.log('Golden adapter: subset/full comparison, actor hash and metadata diffs, full updates and failed-update preservation passed.');
  } finally {fs.rmSync(temporary,{recursive:true,force:true});}
});
