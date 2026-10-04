// SPDX-License-Identifier: MPL-2.0
// Full AI fixtures use temporary internal access, never public test hooks.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.cwd();
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-luau-borders-'));
try {
  fs.cpSync(path.join(root,'src'),path.join(temp,'src'),{recursive:true});
  const module=path.join(temp,'src/simulation/BaseGame.luau');
  const source=fs.readFileSync(module,'utf8');
  const marker='return table.freeze(BaseGame)';
  if(!source.includes(marker))throw new Error('missing BaseGame export');
  // A temporary guard rejects even cache hits: scoring and prices must use their bounded BFS distances.
  const worldFile=path.join(temp,'src/simulation/WorldMap.luau');
  fs.writeFileSync(worldFile,fs.readFileSync(worldFile,'utf8')
    .replace('local WorldMap = {}','local WorldMap = {}\nlocal forbidDistance=false')
    .replace('function WorldMap.distance(map: Map, first: number, second: number): number',
      'function WorldMap.distance(map: Map, first: number, second: number): number\n    assert(not forbidDistance,"border scoring called global distance")')
    .replace('return table.freeze(WorldMap)',
      'WorldMap._forbidDistance=function(value) forbidDistance=value end\nreturn table.freeze(WorldMap)'));
  const internals=`BaseGame._internal={ai=ai,aiBuyTile=aiBuyTile,checkBorderDistances=function(s,c)
    local seen=visible(s,c.ownerId)
    WorldMap._forbidDistance(true)
    local hidden=borderCandidates(s,c,{})
    assert(#hidden==0,"defensive candidate visibility")
    local candidates,distances=borderCandidates(s,c,seen)
    assert(#candidates>0 and bestBorderTile(s,candidates,distances,seen))
    for _, id in candidates do assert(buyTileCost(s,c,distances[id])>0) end
    aiBuyTile(s,c.ownerId)
    WorldMap._forbidDistance(false)
end}\n`;
  fs.writeFileSync(module,source.replace(marker,internals+marker));
  fs.mkdirSync(path.join(temp,'tests/unit'),{recursive:true});
  fs.copyFileSync(path.join(root,'tests/unit/base-borders.luau'),path.join(temp,'tests/unit/base-borders.luau'));
  const result=spawnSync(process.env.LUAU_BIN??'luau',['tests/unit/base-borders.luau'],{cwd:temp,stdio:'inherit',windowsHide:true});
  if(result.error)throw result.error;
  process.exitCode=result.status??1;
  if(result.status===0&&process.argv.includes('--mutations')) {
    const mutations=[
      ['population claim','local yields,maintenance=cityYields(s,p,owner,c,worked,cityTiles,bonus);',
        'if c.population>=3 then for _, id in nearby(s,c.tileId,2) do if not s.tiles[id].ownerId then s.tiles[id].ownerId=owner end end end\n        local yields,maintenance=cityYields(s,p,owner,c,worked,cityTiles,bonus);'],
      ['base rate','+math.max(0,culture)+R.borderBaseRate','+math.max(0,culture)'],
      ['culture pace','^R.borderCultureExponent),"policy")','^R.borderCultureExponent),"production")'],
      ['carry-over','c.borderCulture-=cost; acquireBorderTile(s,c,tileId)','c.borderCulture=0; acquireBorderTile(s,c,tileId)'],
      ['one tile per step','c.borderCulture-=cost; acquireBorderTile(s,c,tileId)',
        'c.borderCulture-=cost; acquireBorderTile(s,c,tileId); if c.borderCulture>=nextTileCost(s,c) then borderStep(s,c,0) end'],
      ['yield score','return 2*y.food+2*y.production','return 0*y.food+2*y.production'],
      ['strategic reveal','return if tile.resource and known[tile.id] then','return if tile.resource and tile.resource~="Iron" and known[tile.id] then'],
      ['territory sight','if tile.ownerId==owner then','if false then'],
      ['territory ring','for _, id in neighbors[tile.id] do set[id]=true end',''],
      ['territory contact','local seen=visible(s,owner); contact(s,owner,seen)','local seen=visible(s,owner)'],
      ['defensive sight','if not seen[id] or (claimed and claimed[id])','if (claimed and claimed[id])'],
      ['radius three','if distances[id]>=3 then','if distances[id]>=4 then'],
      ['adjacency','if s.tiles[neighbor].ownerId==c.ownerId or (claimed and claimed[neighbor]) then','if true then'],
      ['foreign units','or (units[id] and units[id].ownerId~=c.ownerId)',''],
      ['foreign cities','or (cities[id] and cities[id].ownerId~=c.ownerId)',''],
      ['camps','or camps[id] then continue end', 'then continue end'],
      ['candidate ownership','or tile.ownerId or (units[id]','or (units[id]'],
      ['global score distance','extra-3*(d-1)','extra-3*(distance(s,tileId,tileId)+d-1)'],
      ['global price distance','local factor=if d==3','d=distance(s,c.tileId,c.tileId)+d; local factor=if d==3'],
      ['tile tie','value==score and (not best or id<best)','value==score and (not best or id>best)'],
      ['purchase gold','p.gold-=cost; acquireBorderTile(s,c,cmd.tileId,cost)','acquireBorderTile(s,c,cmd.tileId,cost)'],
      ['acquisition count','c.borderTiles=(c.borderTiles or 0)+1','c.borderTiles=(c.borderTiles or 0)'],
      ['private events','if e.kind=="BorderGrowth" and e.ownerId~=actorId then continue end',''],
      ['AI purchase','    aiBuyTile(s,owner)',''],
      ['no-candidate cap','c.borderCulture=math.min(c.borderCulture,cost)','c.borderCulture=c.borderCulture'],
    ];
    for(const [name,from,to] of mutations) {
      if(!source.includes(from))throw new Error(`mutation marker missing: ${name}`);
      fs.writeFileSync(module,source.replace(from,to).replace(marker,internals+marker));
      const changed=spawnSync(process.env.LUAU_BIN??'luau',['tests/unit/base-borders.luau'],{cwd:temp,encoding:'utf8',windowsHide:true});
      if(changed.error)throw changed.error;
      if(changed.status===0||!changed.stderr.includes('function assert'))throw new Error(`mutation did not fail an assertion: ${name}\n${changed.stdout}\n${changed.stderr}`);
      console.log(`Regression mutation rejected: ${name}`);
    }
    console.log(`Border regression mutations: ${mutations.length} rejected by assertions.`);
  }
} finally { fs.rmSync(temp,{recursive:true,force:true}); }
