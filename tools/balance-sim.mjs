// SPDX-License-Identifier: MPL-2.0
// AI-against-AI balance harness runner (not part of the test gate). It copies src into a temporary directory, exposes
// BaseGame's internal turn functions in that copy only (the repository's modules are never changed), runs
// tools/balance-sim.luau there with the official Luau CLI and removes the copy.
//   node tools/balance-sim.mjs [seeds=12] [culture=on|off] [tech,production,growth,policy exponents] [tech floor]
// Optional search overrides affect the temporary copy only.
// Set LUAU_BIN when luau is not on PATH.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.cwd();
const seeds=process.argv[2]??'12';
const culture=process.argv[3]??'on';
const exponents=process.argv[4]?.split(',').map(Number);
if(exponents&&(exponents.length!==4||exponents.some(n=>!Number.isFinite(n))))throw new Error('expected four finite pace exponents');
const techFloor=process.argv[5]===undefined?undefined:Number(process.argv[5]);
if(techFloor!==undefined&&(!exponents||!Number.isInteger(techFloor)||techFloor<1||techFloor>100))throw new Error('tech floor requires exponents and must be 1-100');
if(!/^\d+$/.test(seeds)||!['on','off'].includes(culture))throw new Error('usage: node tools/balance-sim.mjs [seeds] [on|off]');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-luau-balance-'));
try{
  fs.cpSync(path.join(root,'src'),path.join(temp,'src'),{recursive:true});
  if(exponents) {
    const rules=path.join(temp,'src/simulation/BaseRules.luau');
    let source=fs.readFileSync(rules,'utf8');
    ['tech','production','growth','policy'].forEach((category,i)=>{
      const pattern=new RegExp(`(${category}=\\{exponent=)[^,]+`);
      if(!pattern.test(source))throw new Error(`missing ${category} pace curve`);
      source=source.replace(pattern,(_,prefix)=>prefix+exponents[i]);
    });
    if(techFloor!==undefined)source=source.replace(/(tech=\{exponent=[^,]+,minPercent=)\d+/,(_,prefix)=>prefix+techFloor);
    fs.writeFileSync(rules,source);
    console.log(`Pace exponents (tech, production, growth, policy): ${exponents.join(', ')}`);
    if(techFloor!==undefined)console.log(`Tech floor: ${techFloor}`);
  }
  const game=path.join(temp,'src/simulation/BaseGame.luau');
  const source=fs.readFileSync(game,'utf8');
  const marker='return table.freeze(BaseGame)';
  if(!source.includes(marker))throw new Error('BaseGame.luau no longer ends with its frozen export');
  fs.writeFileSync(game,source.replace(marker,'BaseGame._internal={ai=ai,economy=economy,beginTurn=beginTurn,refreshVision=refreshVision,evaluate=evaluate,barbarianTurn=barbarianTurn,scores=scores}\n'+marker));
  fs.copyFileSync(path.join(root,'tools/balance-sim.luau'),path.join(temp,'balance-sim.luau'));
  const result=spawnSync(process.env.LUAU_BIN??'luau',['balance-sim.luau','-a',seeds,culture],{cwd:temp,stdio:'inherit'});
  if(result.error)throw result.error;
  if(result.status!==0)process.exitCode=result.status??1;
}finally{
  fs.rmSync(temp,{recursive:true,force:true});
}
