// SPDX-License-Identifier: MPL-2.0
// Original sentry regression runner: temporary internal access and bounded isolated mutations, never public hooks.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.cwd();
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-luau-sentry-'));
try {
  fs.cpSync(path.join(root,'src'),path.join(temp,'src'),{recursive:true});
  fs.mkdirSync(path.join(temp,'tests/unit'),{recursive:true});
  fs.copyFileSync(path.join(root,'tests/unit/base-sentry.luau'),path.join(temp,'tests/unit/base-sentry.luau'));
  const game=path.join(temp,'src/simulation/BaseGame.luau');
  const save=path.join(temp,'src/simulation/BaseSave.luau');
  const source=fs.readFileSync(game,'utf8').replaceAll('\r\n','\n');
  const saveSource=fs.readFileSync(save,'utf8').replaceAll('\r\n','\n');
  const marker='return table.freeze(BaseGame)';
  if(!source.includes(marker))throw new Error('missing BaseGame export');
  const instrument=text=>text.replace(marker,'BaseGame._internal={barbarianAct=barbarianAct}\n'+marker);
  function run() {
    const result=spawnSync(process.env.LUAU_BIN??'luau',['tests/unit/base-sentry.luau','-a','internal'],{cwd:temp,encoding:'utf8',windowsHide:true});
    if(result.error)throw result.error;
    return result;
  }
  fs.writeFileSync(game,instrument(source));
  const baseline=run();
  process.stdout.write(baseline.stdout); process.stderr.write(baseline.stderr);
  if(baseline.status!==0)throw new Error('sentry internal fixtures failed');
  const mutations=[
    ['command schema',game,'SentryUnit={unitId=true},',''],
    ['settler refusal',game,'if u.kind=="Settler" then return reject("A settler cannot sentry.") end',''],
    ['busy refusal',game,'if u.work then return reject("A unit building an improvement is already busy.") end',''],
    ['duplicate refusal',game,'if u.sentry then return reject("This unit is already on sentry.") end',''],
    ['accepted command clears',game,'if cmd.kind~="SentryUnit" then u.sentry=nil end',''],
    ['turn-start waking',game,'wakeSentries(s,owner)\nend','-- removed waking\nend'],
    ['mid-turn movement waking',game,'wakeAfterAction(s,unit.ownerId,from,target,witnesses); return true','return true'],
    ['barbarian movement waking',game,'wakeAfterAction(s,u.ownerId,from,best,witnesses)',''],
    ['attack waking',game,'wakeAfterAction(s,unit.ownerId,from,target,witnesses)\nend','-- removed waking\nend'],
    ['peaceful rival filter',game,'hostile(s,owner,u.ownerId) and seen[u.tileId]','owner~=u.ownerId and seen[u.tileId]'],
    ['wake distance',game,'nearby(s,u.tileId,2)','nearby(s,u.tileId,3)'],
    ['own-only unit view',game,'else view.xp=nil; view.sentry=nil end','else view.xp=nil end'],
    ['owner-private waking event',game,'or e.kind=="UnitWoke"',''],
    ['save field round-trip',save,'promotions work sentry"','promotions work"'],
    ['save boolean validation',save,'type(u.sentry)~="boolean"','false'],
    ['save waking event kind',save,',UnitWoke=true',''],
  ];
  for(const [name,file,needle,replacement] of mutations) {
    const original=file===game?source:saveSource;
    if(!original.includes(needle))throw new Error(`missing mutation marker: ${name}`);
    fs.writeFileSync(game,instrument(file===game?original.replace(needle,replacement):source));
    fs.writeFileSync(save,file===save?original.replace(needle,replacement):saveSource);
    const result=run();
    if(result.status===0)throw new Error(`undetected sentry regression: ${name}`);
    if(/SyntaxError|CompileError/.test(result.stderr))throw new Error(`invalid mutation: ${name}: ${result.stderr}`);
    console.log(`Sentry mutation detected: ${name}`);
  }
  console.log(`Sentry: internal fixtures passed; ${mutations.length} regression mutations detected.`);
} finally {
  // mkdtemp yields a new absolute OS-temp child; verify containment before recursive cleanup.
  const parent=path.resolve(os.tmpdir());
  if(path.dirname(path.resolve(temp))!==parent||!path.basename(temp).startsWith('unciv-luau-sentry-'))throw new Error('unsafe temporary cleanup path');
  fs.rmSync(temp,{recursive:true,force:true});
}
