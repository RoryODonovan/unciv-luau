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
      encoding:'utf8',env:{...process.env,LUAU_BIN:process.execPath,CI:'',GITHUB_ACTIONS:'',GOLDEN_FULL:'',GOLDEN_UPDATE:'',...env},
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

function guardedRunner(check) {
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-golden-guard-'));
  try {
    const runner=path.join(temporary,'run.mjs');
    const baselinePath=path.join(temporary,'baseline.json');
    const tracePath=path.join(temporary,'trace.log');
    const preload=path.join(temporary,'intercept.cjs');
    fs.copyFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)),'run.mjs'),runner);
    const config={presets:[{name:'Quick'}],shapes:['Hex'],seeds:[1],defaultSeedCount:1};
    const games=[{id:'Quick/Hex/seed-1/barbarians-on'}];
    const original=JSON.stringify({config,games})+'\n';
    fs.writeFileSync(baselinePath,original);
    fs.writeFileSync(path.join(temporary,'replay-corpus.luau'),`
      console.log('GOLDEN_CONFIG '+${JSON.stringify(JSON.stringify(config))});
      console.log('GOLDEN_GAME '+${JSON.stringify(JSON.stringify(games[0]))});
    `);
    // Intercept the adapter's actual spawn and baseline writes, including attempted writes that fail.
    fs.writeFileSync(preload,`
      const fs=require('node:fs'), cp=require('node:child_process');
      const write=fs.writeFileSync.bind(fs);
      const record=event=>write(process.env.GOLDEN_TEST_TRACE,event+'\\n',{flag:'a'});
      for(const [target,name] of [[cp,'spawn'],[fs,'writeFileSync'],[fs,'renameSync']]) {
        const original=target[name];
        target[name]=function(...args) {record(name); return original.apply(this,args);};
      }
      require('node:module').syncBuiltinESMExports();
    `);
    const run=(env={})=>{
      fs.writeFileSync(tracePath,'');
      const result=spawnSync(process.execPath,['--require',preload,runner],{
        encoding:'utf8',env:{...process.env,LUAU_BIN:process.execPath,CI:'',GITHUB_ACTIONS:'',
          GOLDEN_FULL:'',GOLDEN_UPDATE:'',GOLDEN_TEST_TRACE:tracePath,...env},
      });
      return {...result,trace:fs.readFileSync(tracePath,'utf8')};
    };
    const control=run({GOLDEN_UPDATE:'1'});
    assert.equal(control.status,0,control.stderr);
    assert.equal(control.trace,'spawn\nwriteFileSync\nrenameSync\n','interceptors must observe a successful local update');
    fs.writeFileSync(baselinePath,original);
    check({run,baselinePath,original});
  } finally {fs.rmSync(temporary,{recursive:true,force:true});}
}

test('update in CI is refused before Luau or any baseline write',()=>guardedRunner(({run,baselinePath,original})=>{
  for(const env of [{CI:'1'},{CI:'false'},{GITHUB_ACTIONS:'true'}]) {
    const result=run({...env,GOLDEN_UPDATE:'1'});
    assert.equal(result.status,1,result.stderr);
    assert.match(result.stderr,/GOLDEN_UPDATE is not allowed in CI; regenerate the baseline locally and commit it/);
    assert.equal(result.trace,'','CI refusal must precede every spawn and write');
    assert.equal(fs.readFileSync(baselinePath,'utf8'),original);
  }
}));

test('compare requires a readable committed baseline before Luau runs',()=>guardedRunner(({run,baselinePath})=>{
  fs.unlinkSync(baselinePath);
  let result=run({CI:'true'});
  assert.equal(result.status,1,result.stderr);
  assert.match(result.stderr,/Cannot read committed golden baseline:.*ENOENT/);
  assert.equal(result.trace,'','missing baseline must not spawn Luau or write a replacement');
  assert.equal(fs.existsSync(baselinePath),false);
  // A directory is unreadable as baseline JSON on Windows and on the public Linux CI runner.
  fs.mkdirSync(baselinePath);
  result=run();
  assert.equal(result.status,1,result.stderr);
  assert.match(result.stderr,/Cannot read committed golden baseline:/);
  assert.equal(result.trace,'','unreadable baseline must not spawn Luau or write a replacement');
}));
