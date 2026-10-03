// SPDX-License-Identifier: MPL-2.0
// Luau CLI has no filesystem/environment API. This adapter handles baseline I/O; engine execution stays in Luau.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {isDeepStrictEqual} from 'node:util';
import {performance} from 'node:perf_hooks';

const directory=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(directory,'../..');
const baselinePath=path.join(directory,'baseline.json');
const update=process.env.GOLDEN_UPDATE==='1';
if(update&&(process.env.CI||process.env.GITHUB_ACTIONS==='true')) {
  console.error('GOLDEN_UPDATE is not allowed in CI; regenerate the baseline locally and commit it');
  process.exit(1);
}
// Updates always run the full matrix, so a default invocation cannot erase unselected baselines.
const full=update||process.env.GOLDEN_FULL==='1';
if(update)console.warn('WARNING: GOLDEN_UPDATE=1 — replacing ALL golden hashes. Explain every behavioural change in the PR.');
let baseline=null;
if(!update) {
  try {baseline=JSON.parse(fs.readFileSync(baselinePath,'utf8'));}
  catch(error) {
    console.error(`Cannot read committed golden baseline: ${error.message}`);
    process.exit(1);
  }
}
const started=performance.now();
const games=[];
let config, expectedIds, failure, pending='';

function ids(c, count) {
  return c.presets.flatMap(p=>c.shapes.flatMap(shape=>c.seeds.slice(0,count).map((seed,index)=>
    `${p.name}/${shape}/seed-${seed}/barbarians-${index%2===0?'on':'off'}`)));
}
function diff(expected, actual, location) {
  if(isDeepStrictEqual(expected,actual))return;
  if(expected&&actual&&typeof expected==='object'&&typeof actual==='object'&&Array.isArray(expected)===Array.isArray(actual)) {
    for(const key of new Set([...Object.keys(expected),...Object.keys(actual)])) {
      const label=Array.isArray(actual)&&actual[key]?.checkpoint?`[${actual[key].checkpoint}]`:`.${key}`;
      diff(expected[key],actual[key],location+label);
    }
  } else {
    throw new Error(`GOLDEN MISMATCH ${location}: expected ${JSON.stringify(expected)??'<missing>'}, actual ${JSON.stringify(actual)??'<missing>'}`);
  }
}
function line(text) {
  if(text.startsWith('GOLDEN_CONFIG ')) {
    if(config)throw new Error('Duplicate golden configuration');
    config=JSON.parse(text.slice(14));
    expectedIds=ids(config,full?config.seeds.length:config.defaultSeedCount);
    if(baseline) {
      diff(baseline.config,config,'configuration');
      diff(ids(config,config.seeds.length),baseline.games.map(g=>g.id),'baseline game matrix');
    }
  } else if(text.startsWith('GOLDEN_GAME ')) {
    if(!config)throw new Error('Missing golden configuration');
    const game=JSON.parse(text.slice(12));
    if(game.id!==expectedIds[games.length])throw new Error(`Unexpected golden game ${game.id}`);
    if(baseline)diff(baseline.games.find(g=>g.id===game.id),game,game.id);
    games.push(game);
    console.log(`Golden ${games.length}/${expectedIds.length}: ${game.id}, ${game.victoryType} at round ${game.finalRound}`);
  } else if(text)console.log(text);
}

const child=spawn(process.env.LUAU_BIN??'luau',[path.join(directory,'replay-corpus.luau'),'-a',full?'full':'default'],
  {cwd:root,windowsHide:true,stdio:['ignore','pipe','inherit']});
child.stdout.setEncoding('utf8');
child.stdout.on('data',chunk=>{
  if(failure)return;
  pending+=chunk;
  const lines=pending.split(/\r?\n/); pending=lines.pop();
  try {for(const text of lines)line(text);} catch(error) {failure=error; child.kill();}
});
child.on('error',error=>{failure=error;});
child.on('close',code=>{
  try {
    if(failure)throw failure;
    if(code!==0)throw new Error(`Golden Luau replay failed with status ${code}`);
    if(pending)line(pending);
    if(!config||games.length!==expectedIds.length)throw new Error('Incomplete golden corpus; baseline was not written');
    if(update) {
      // Only replace after all games and resume assertions succeed. An interrupted update leaves the old file intact.
      const temporary=baselinePath+'.tmp';
      fs.writeFileSync(temporary,JSON.stringify({config,games},null,2)+'\n');
      fs.renameSync(temporary,baselinePath);
      console.warn(`WARNING: replaced baseline.json with ${games.length} games; review the diff before committing.`);
    }
    console.log(`Golden ${full?'full':'default'}: ${games.length} games passed, 12 resume replays; wall ${(performance.now()-started)/1000}s.`);
  } catch(error) {console.error(error.message); process.exitCode=1;}
});
