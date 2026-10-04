// SPDX-License-Identifier: MPL-2.0
// Reproducible full-AI-turn timing on the largest sphere, with cold restored states.
// Temporary internals only; the public engine exports no test hooks.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-border-perf-'));
try {
  fs.cpSync('src',path.join(temp,'src'),{recursive:true});
  const file=path.join(temp,'src/simulation/BaseGame.luau');
  fs.writeFileSync(file,fs.readFileSync(file,'utf8').replace('return table.freeze(BaseGame)',
    'BaseGame._internal={ai=ai,beginTurn=beginTurn}\nreturn table.freeze(BaseGame)'));
  fs.writeFileSync(path.join(temp,'perf.luau'),`-- SPDX-License-Identifier: MPL-2.0
local Game=require("./src/simulation/BaseGame")
local Map=require("./src/simulation/WorldMap")
local I=Game._internal
local s=Game.new(7919,{mapShape="Sphere",frequency=22,maxTurns=120,barbarians=false})
for _, u in s.units do if u.ownerId==1 and u.kind=="Settler" then
    assert(Game.apply(s,1,{kind="FoundCity",unitId=u.id}).ok); break
end end
s.players[1].gold=1000
local map=Map.fromSphereTiles(s.tiles,s.frequency)
-- A developed capital with a resource-rich second ring and the starting military/workers.

local home=s.cities[2]
for _, id in Map.range(map,home.tileId,2) do
    if Map.distance(map,home.tileId,id)==2 then s.tiles[id].terrain="Plains"; s.tiles[id].feature=nil; s.tiles[id].resource="Gold" end
end
home.population=8; home.queue=""; home.borderCulture=100
local raw=Game.serialize(s)
local times={}
for pass=1,12 do
    local state=assert(Game.restore(raw)); state.players[1].human=false; I.beginTurn(state,1)
    local start=os.clock(); I.ai(state,1); local elapsed=(os.clock()-start)*1000
    if pass>2 then table.insert(times,elapsed) end
end
table.sort(times)
print(string.format("Sphere frequency 22 (%d tiles), full AI turn: median %.3f ms, range %.3f-%.3f ms (10 cold-state samples, 2 warmups)",#s.tiles,(times[5]+times[6])/2,times[1],times[10]))
`);
  const result=spawnSync(process.env.LUAU_BIN??'luau',['perf.luau'],{cwd:temp,stdio:'inherit',windowsHide:true});
  if(result.error)throw result.error;
  process.exitCode=result.status??1;
} finally {fs.rmSync(temp,{recursive:true,force:true});}
