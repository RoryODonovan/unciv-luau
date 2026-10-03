--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original layered Cartesian geography and bounded graph-based starting regions.
-- This is a small civilization ruleset generator, not an Unciv map-generation port.
export type Center = {read x: number, read y: number, read z: number}
-- `feature` is an optional terrain feature (Forest, Jungle, Marsh or Oasis). `river` is an optional edge mask: bit k
-- (value 2^k) marks a river on the edge to the tile's (k+1)-th neighbour in the supplied adjacency list. Callers pass
-- ascending neighbour lists (both WorldMap topologies do), so the mask indexes neighbours in ascending id order. Both
-- sides of a river edge carry the bit, and rivers only separate two passable land tiles.
export type Tile = {id: number, terrain: string, resource: string?, feature: string?, river: number?}
export type Diagnostics = {landFraction: number, passableFraction: number, largestPassableFraction: number, startDistance: number, repairs: number, resourceFraction: number, startFood: {number}, startProduction: {number}, featureFraction: number, rivers: number, riverFraction: number}
export type Result = {tiles: {Tile}, starts: {number}, diagnostics: Diagnostics}
local Generation={}
local MOD=2147483647
local function hash(seed: number,x: number,y: number,z: number): number
 local n=(seed+x*104729+y*130363+z*155921)%MOD
 n=(n*48271)%MOD;n=bit32.bxor(n,bit32.rshift(n,11));n=(n*40699)%MOD
 return n/MOD
end
local function smooth(t: number): number return t*t*(3-2*t)end
local function noise(seed: number,x: number,y: number,z: number): number
 local ix,iy,iz=math.floor(x),math.floor(y),math.floor(z)
 local fx,fy,fz=smooth(x-ix),smooth(y-iy),smooth(z-iz)
 local total=0
 for dx=0,1 do for dy=0,1 do for dz=0,1 do
  total+=(hash(seed,ix+dx,iy+dy,iz+dz)*2-1)*(if dx==0 then 1-fx else fx)*(if dy==0 then 1-fy else fy)*(if dz==0 then 1-fz else fz)
 end end end
 return total
end
local function passable(tile: Tile): boolean return tile.terrain~='Water' and tile.terrain~='Mountain'end
-- Game-rule natural yields (BaseRules terrains and features): Forest, Jungle and Oasis replace the terrain's yields and
-- Marsh takes one food from it.
local function food(tile: Tile): number
 local f=tile.feature
 local base=if f=='Forest' then 1 elseif f=='Jungle' then 2 elseif f=='Oasis' then 3
  elseif tile.terrain=='Grassland' then 3 elseif tile.terrain=='Plains' then 2 elseif tile.terrain=='Forest' or tile.terrain=='Hills' or tile.terrain=='Tundra' then 1 else 0
 if f=='Marsh' then base=math.max(0,base-1)end
 return base+(if tile.resource=='Wheat' or tile.resource=='Deer' then 1 else 0)
end
local function production(tile: Tile): number
 local f=tile.feature
 local base=if f=='Forest' then 2 elseif f=='Jungle' or f=='Oasis' then 0
  elseif tile.terrain=='Hills' or tile.terrain=='Forest'then 2 elseif tile.terrain=='Plains' or tile.terrain=='Desert'then 1 else 0
 return base+(if tile.resource=='Iron' or tile.resource=='Horses' or tile.resource=='Saltpeter' or tile.resource=='Oil' then 1 else 0)
end
-- Resources a feature keeps (their improvement may be built on it): Deer and Spices in Forest, Spices in Jungle.
local function featureAllows(feature: string?,resource: string?): boolean
 if not feature or not resource then return true end
 if feature=='Forest' then return resource=='Deer' or resource=='Spices' end
 return feature=='Jungle' and resource=='Spices'
end
-- Rivers follow tile edges. A corner where three mutually adjacent tiles meet is a river vertex; the edge between tiles
-- a and b joins the two corners whose triples contain both. From high corners whose three tiles are all passable land, a
-- river walks to the lowest neighbouring corner while that is strictly lower, never through a corner touching a
-- mountain, and ends where it reaches a corner touching water or an earlier river (a tributary). A walk that stops in a
-- local minimum, or is shorter than three edges, is discarded. Sources are taken highest first (with a small seeded
-- jitter) and must be clear of earlier rivers' tiles and their neighbours. Strictly falling height makes every walk
-- finite and the fixed iteration order makes it deterministic.
local function carveRivers(tiles: {Tile},neighbors: {{number}},height: {number},fieldSeed: number): number
 local count=#tiles
 local passableCount=0;for _,tile in tiles do if passable(tile)then passableCount+=1 end end
 local target=math.floor(passableCount/55)
 if target<=0 then return 0 end
 local position: {{[number]: number}}={}
 for a=1,count do local m={};for k,b in neighbors[a]do m[b]=k end;position[a]=m end
 local va: {number},vb: {number},vc: {number}={},{},{}
 local edgeVertices: {[number]: {number}}={}
 local function edgeKey(a: number,b: number): number if a>b then a,b=b,a end;return a*8192+b end
 local function link(key: number,v: number) local list=edgeVertices[key];if list then table.insert(list,v)else edgeVertices[key]={v}end end
 for a=1,count do
  local list=neighbors[a]
  for _,b in list do
   if b<=a then continue end
   for _,c in list do
    if c<=b or not position[b][c]then continue end
    local v=#va+1;va[v],vb[v],vc[v]=a,b,c
    link(edgeKey(a,b),v);link(edgeKey(b,c),v);link(edgeKey(a,c),v)
   end
  end
 end
 -- 0: all three tiles passable land; 1: a mouth (touches water); 2: blocked (touches a mountain, no water).
 local kinds: {number}={};local heights: {number}={}
 for v=1,#va do
  local ta,tb,tc=tiles[va[v]].terrain,tiles[vb[v]].terrain,tiles[vc[v]].terrain
  kinds[v]=if ta=='Water' or tb=='Water' or tc=='Water' then 1 elseif ta=='Mountain' or tb=='Mountain' or tc=='Mountain' then 2 else 0
  heights[v]=height[va[v]]+height[vb[v]]+height[vc[v]]
 end
 -- Steepest descent is a fixed property of a corner, computed once: the strictly lowest neighbouring corner that does not
 -- touch a mountain (0 when none) and the edge leading to it. Ties keep the first in edge order (a-b, b-c, a-c).
 local down: {number}={};local downA: {number}={};local downB: {number}={}
 local function descend(v: number): number
  local cached=down[v];if cached then return cached end
  local best,bestHeight,bx,by=0,heights[v],0,0
  local a,b,c=va[v],vb[v],vc[v]
  for pair=1,3 do
   local x,y=if pair==1 then a elseif pair==2 then b else a,if pair==1 then b else c
   for _,other in edgeVertices[edgeKey(x,y)]do
    if other~=v and kinds[other]~=2 and heights[other]<bestHeight then best,bestHeight,bx,by=other,heights[other],x,y end
   end
  end
  down[v]=best;downA[v]=bx;downB[v]=by
  return best
 end
 local sources: {number}={};local score: {number}={}
 for v=1,#va do if kinds[v]==0 then table.insert(sources,v);score[v]=heights[v]+hash(fieldSeed+293,v,0,0)*.06 end end
 table.sort(sources,function(a: number,b: number): boolean return if score[a]==score[b] then a<b else score[a]>score[b] end)
 local masks: {[number]: number}={};local onRiver: {[number]: boolean}={};local near: {[number]: boolean}={}
 -- A corner whose descent ended in a local minimum leads there again from any later walk: a later river could only pass
 -- it by following the same descent, so it would fail too. Marking such corners skips repeated walks without changing
 -- which rivers are kept.
 local dead: {[number]: boolean}={}
 local made=0
 for _,source in sources do
  if made>=target then break end
  if dead[source] or near[va[source]] or near[vb[source]] or near[vc[source]] then continue end
  local corners={source};local current=source;local reached,stuck=false,false
  while true do
   local best=descend(current)
   if best==0 or dead[best] then stuck=true;break end
   table.insert(corners,best)
   if kinds[best]==1 or onRiver[best] then reached=true;break end
   current=best
  end
  if stuck then for _,corner in corners do dead[corner]=true end end
  if not reached or #corners<4 then continue end
  for index=1,#corners-1 do
   local corner=corners[index];local x,y=downA[corner],downB[corner]
   masks[x]=bit32.bor(masks[x] or 0,bit32.lshift(1,position[x][y]-1))
   masks[y]=bit32.bor(masks[y] or 0,bit32.lshift(1,position[y][x]-1))
   near[x]=true;near[y]=true
   for _,other in neighbors[x]do near[other]=true end
   for _,other in neighbors[y]do near[other]=true end
  end
  for _,corner in corners do onRiver[corner]=true end
  made+=1
 end
 for id,mask in masks do tiles[id].river=mask end
 return made
end
local function disk(neighbors: {{number}},source: number,radius: number,marks: {number},stamp: number,tiles: {Tile}?): {number}
 local queue={source};local depth={0};marks[source]=stamp;local head=1
 while head<=#queue do
  local id=queue[head];local d=depth[head];head+=1
  if d>=radius then continue end
  for _,other in neighbors[id]do if marks[other]~=stamp and (not tiles or passable(tiles[other]))then marks[other]=stamp;table.insert(queue,other);table.insert(depth,d+1)end end
 end
 return queue
end
local function components(tiles: {Tile},neighbors: {{number}}): ({number},number)
 local labels: {number}={};local biggest: {number}={};local component=0
 for id,tile in tiles do
  if not passable(tile)or labels[id]then continue end
  component+=1;local queue={id};local head=1;labels[id]=component
  while head<=#queue do
   local current=queue[head];head+=1
   for _,other in neighbors[current]do if not labels[other]and passable(tiles[other])then labels[other]=component;table.insert(queue,other)end end
  end
  if #queue>#biggest then biggest=queue end
 end
 return biggest,component
end
local function distances(tiles: {Tile},neighbors: {{number}},source: number): ({number},number)
 local result: {number}={};result[source]=0;local queue={source};local head,maximum=1,0
 while head<=#queue do
  local id=queue[head];head+=1
  for _,other in neighbors[id]do if result[other]==nil and passable(tiles[other])then
   local d=result[id]+1;result[other]=d;maximum=math.max(maximum,d);table.insert(queue,other)
  end end
 end
 return result,maximum
end
function Generation.generate(seed: number,centers: {Center},neighbors: {{number}},shape: 'Sphere'|'Hex'): Result
 assert(seed==seed and math.abs(seed)<=9007199254740991 and seed%1==0,'seed must be a finite safe integer')
 assert(shape=='Sphere' or shape=='Hex','shape must be Sphere or Hex')
 local count=#centers;assert(count>=12 and count<=4921 and #neighbors==count,'bounded complete topology required')
 for id,p in centers do
  assert(p.x==p.x and p.y==p.y and p.z==p.z and math.abs(p.x)<=2 and math.abs(p.y)<=2 and math.abs(p.z)<=2,'normalized finite centers required')
  assert(#neighbors[id]>=2 and #neighbors[id]<=6,'invalid topology degree')
  for _,other in neighbors[id]do assert(other%1==0 and other>=1 and other<=count and other~=id,'invalid neighbor')end
 end
 local state=seed%MOD;if state==0 then state=1 end
 local function roll(): number state=(state*48271)%MOD;return state/MOD end
 local fieldSeed=math.floor(roll()*MOD)
 local function direction(): Center
  local y=roll()*2-1;local angle=roll()*math.pi*2;local r=math.sqrt(1-y*y)
  return {x=r*math.cos(angle),y=y,z=r*math.sin(angle)}
 end
 local continent=direction();local tangent=direction()
 local projection=continent.x*tangent.x+continent.y*tangent.y+continent.z*tangent.z
 local tx,ty,tz=tangent.x-continent.x*projection,tangent.y-continent.y*projection,tangent.z-continent.z*projection
 local length=math.sqrt(tx*tx+ty*ty+tz*tz);tx,ty,tz=tx/length,ty/length,tz/length
 local bx,by,bz=continent.y*tz-continent.z*ty,continent.z*tx-continent.x*tz,continent.x*ty-continent.y*tx
 local angleA,angleB=1.05+roll()*.5,1.35+roll()*.5
 local bend=.9+roll()*1.4
 local lobeA={x=continent.x*math.cos(angleA)+tx*math.sin(angleA),y=continent.y*math.cos(angleA)+ty*math.sin(angleA),z=continent.z*math.cos(angleA)+tz*math.sin(angleA)}
 local lobeB={x=continent.x*math.cos(angleB)+(tx*math.cos(bend)+bx*math.sin(bend))*math.sin(angleB),y=continent.y*math.cos(angleB)+(ty*math.cos(bend)+by*math.sin(bend))*math.sin(angleB),z=continent.z*math.cos(angleB)+(tz*math.cos(bend)+bz*math.sin(bend))*math.sin(angleB)}
 local mainWidth=.34+roll()*.1;local armWidth=.48+roll()*.14;local tipWidth=.55+roll()*.13
 local island=direction();local rangeA=direction();local rangeB=direction()
 local coastAmplitude=if count<=64 then .2 else .33+roll()*.16
 local rotation=roll()*math.pi*2;local cx,cz=(roll()-.5)*.35,(roll()-.5)*.35
 local cosine,sine=math.cos(rotation),math.sin(rotation)
 local tiles: {Tile}={};local moisture: {number}={};local temperature: {number}={};local elevation: {number}={};local resourceField: {number}={};local resourceKind: {number}={};local bog: {number}={};local spring: {number}={};local deposit: {number}={};local depositKind: {number}={}
 for id,p in centers do
  -- Cartesian domain warping has no longitude seam or pole coordinate singularity.
  local wx=p.x+noise(fieldSeed+11,p.x*1.8,p.y*1.8,p.z*1.8)*.18
  local wy=p.y+noise(fieldSeed+23,p.x*1.8,p.y*1.8,p.z*1.8)*.18
  local wz=p.z+noise(fieldSeed+37,p.x*1.8,p.y*1.8,p.z*1.8)*.18
  local broad=noise(fieldSeed+53,wx*2.4,wy*2.4,wz*2.4)
  local shore=noise(fieldSeed+71,wx*5.1,wy*5.1,wz*5.1)
  local land: number
  if shape=='Sphere' then
   local main=wx*continent.x+wy*continent.y+wz*continent.z-mainWidth
   local arm=wx*lobeA.x+wy*lobeA.y+wz*lobeA.z-armWidth
   local tip=wx*lobeB.x+wy*lobeB.y+wz*lobeB.z-tipWidth
   land=math.max(main,arm,tip)+broad*coastAmplitude+shore*(if count<=64 then .035 else .11)
   if count>64 then land=math.max(land,(wx*island.x+wy*island.y+wz*island.z-.96)*.9+shore*.035)end
  else
   local x,z=wx-cx,wz-cz;local u,v=x*cosine+z*sine,-x*sine+z*cosine
   land=math.max(.5-u*u*.95-v*v*.85,.22-(u-.53)^2*2.3-(v+.3)^2*2.8,.16-(u+.52)^2*3.6-(v-.35)^2*3.1)+broad*coastAmplitude+shore*.1
  end
  elevation[id]=land
  local lake=noise(fieldSeed+97,wx*4.2,wy*4.2,wz*4.2)
  local signedA=wx*rangeA.x+wy*rangeA.y+wz*rangeA.z+noise(fieldSeed+109,wx*2.7,wy*2.7,wz*2.7)*.19
  local signedB=wx*rangeB.x+wy*rangeB.y+wz*rangeB.z+noise(fieldSeed+127,wx*2.7,wy*2.7,wz*2.7)*.19-.28
  local ridge=math.min(math.abs(signedA),math.abs(signedB))
  local belt=noise(fieldSeed+149,wx*2.9,wy*2.9,wz*2.9)
  local latitude=math.abs(if shape=='Sphere' then p.y else p.z)
  local heat=1-latitude+noise(fieldSeed+163,wx*2,wy*2,wz*2)*.13
  local wet=noise(fieldSeed+181,wx*2.8,wy*2.8,wz*2.8)-math.max(0,1-math.abs(latitude-.34)/.32)*.13
  moisture[id]=wet;temperature[id]=heat
  local terrain: string;local feature: string?=nil
  if land<0 or land>.22 and lake>.54 then terrain='Water'
  elseif ridge<.055 and belt>.04 and land>.04 then terrain='Mountain'
  elseif ridge<.18 and belt>-.3 then terrain='Hills'
  elseif heat<.24 then terrain='Tundra';if wet>.16 then feature='Forest' end
  elseif heat>.37 and wet<-.22 then terrain='Desert'
  -- Wet lowlands carry woods as a feature on their own terrain: Jungle in the hot belt, Forest elsewhere.
  elseif wet>.16 then terrain=if wet>.3 then 'Grassland' else 'Plains';feature=if heat>.66 then 'Jungle' else 'Forest'
  elseif wet>-.04 then terrain='Grassland'
  else terrain='Plains'end
  tiles[id]={id=id,terrain=terrain,feature=feature}
  resourceField[id]=noise(fieldSeed+211,wx*5.4,wy*5.4,wz*5.4)
  resourceKind[id]=noise(fieldSeed+233,wx*3.1,wy*3.1,wz*3.1)
  bog[id]=noise(fieldSeed+277,wx*4.6,wy*4.6,wz*4.6)
  spring[id]=noise(fieldSeed+283,wx*6.3,wy*6.3,wz*6.3)
  deposit[id]=noise(fieldSeed+307,wx*4.8,wy*4.8,wz*4.8);depositKind[id]=noise(fieldSeed+313,wx*2.6,wy*2.6,wz*2.6)
 end
 if count<=20 then
  -- The existing frequency-one toy globe has graph diameter three. Preserve one
  -- ocean tile and enough land for two nonoverlapping capital neighborhoods.
  local ocean=1;for id=2,count do if elevation[id]<elevation[ocean]then ocean=id end end
  for id,tile in tiles do
   if id==ocean then tile.terrain='Water';tile.feature=nil
   elseif tile.terrain=='Water' or tile.terrain=='Tundra' or tile.terrain=='Desert'then tile.terrain=if moisture[id]>0 then 'Grassland' else 'Plains'
   elseif tile.terrain=='Mountain'then tile.terrain='Hills'end
  end
 end
 -- Coasts retain greener lowlands. Relief remains a separate layer.
 for id,tile in tiles do
  if tile.terrain=='Plains' or tile.terrain=='Grassland' or tile.terrain=='Desert'then
   local coast=false;for _,other in neighbors[id]do if tiles[other].terrain=='Water'then coast=true;break end end
   if coast and moisture[id]>-.15 then tile.terrain='Grassland'end
  end
  -- Marsh fills patches of featureless low coastal grassland; an Oasis is a rare isolated desert spring.
  if tile.terrain=='Grassland' and not tile.feature and elevation[id]<.09 and bog[id]>.08 then tile.feature='Marsh' end
  if tile.terrain=='Desert' and spring[id]>.22 then
   local isolated=true;for _,other in neighbors[id]do if tiles[other].feature=='Oasis' then isolated=false;break end end
   if isolated then tile.feature='Oasis' end
  end
  if resourceField[id]>.13 then
   local choose=resourceKind[id]
   if tile.feature=='Forest'then if tile.terrain~='Tundra' then tile.resource=if choose>-.04 and temperature[id]>.42 then 'Spices' else 'Deer' end
   elseif tile.feature=='Jungle'then tile.resource='Spices'
   elseif tile.feature then
   elseif tile.terrain=='Hills'then tile.resource=if choose>0 then 'Iron' else 'Gold'
   elseif tile.terrain=='Plains' or tile.terrain=='Grassland'then tile.resource=if choose>-.04 then 'Wheat' else 'Horses'
   elseif tile.terrain=='Desert'then tile.resource='Gold'end
  end
 end
 local biggest=components(tiles,neighbors);local repairs=0
 local function broaden(): boolean
  local members: {[number]: boolean}={};for _,id in biggest do members[id]=true end
  local selected: number?=nil;local best=-math.huge
  for id,tile in tiles do
   if passable(tile)then continue end
   local adjacent=0;for _,other in neighbors[id]do if members[other]then adjacent+=1 end end
   if adjacent==0 then continue end
   -- A mountain pass is preferable to filling a bay. Two-sided frontier edits
   -- expand a compact region; they never draw a line between chosen capitals.
   local score=adjacent*5+(if tile.terrain=='Mountain'then 12 else 0)+elevation[id]+hash(fieldSeed+241,id,0,0)*.1
   if score>best then selected,best=id,score end
  end
  if not selected then return false end
  tiles[selected].terrain=if tiles[selected].terrain=='Mountain'then 'Hills' else 'Plains'
  tiles[selected].resource=nil;tiles[selected].feature=nil;repairs+=1;biggest=components(tiles,neighbors);return true
 end
 local minimumMainland=if count<=64 then math.max(8,math.ceil(count*.32))else 8
 for _=1,16 do if #biggest>=minimumMainland then break end;if not broaden()then break end end
 local marks: {number}={};local stamp=0
 local function choose(): (number?,number?,{number})
  local scores: {number}={};local candidates: {number}={}
  for _,id in biggest do
   local free=0;for _,other in neighbors[id]do if passable(tiles[other])then free+=1 end end
   if free<3 then continue end
   stamp+=1;local localIds=disk(neighbors,id,2,marks,stamp,tiles)
   local f,p,resources=0,0,0;local kinds: {[string]: boolean}={}
   for _,near in localIds do
    local t=tiles[near];f+=food(t);p+=production(t)
    if t.resource and not kinds[t.resource]then kinds[t.resource]=true;resources+=1 end
   end
   local centerBonus=if (tiles[id].terrain=='Grassland' or tiles[id].terrain=='Plains') and not tiles[id].feature then 5 else 0
   scores[id]=math.min(f,22)*.55+math.min(p,18)*.6+math.min(resources,4)*2+centerBonus
   table.insert(candidates,id)
  end
  if #candidates<2 then return nil,nil,{}end
  local first,best=candidates[1],-math.huge
  for _,id in candidates do local score=scores[id]+hash(fieldSeed+251,id,0,0)*6;if score>best then first,best=id,score end end
  local distance,maximum=distances(tiles,neighbors,first)
  stamp+=1;local excluded: {[number]: boolean}={};for _,id in disk(neighbors,first,2,marks,stamp,nil)do excluded[id]=true end
  local separation=math.max(3,math.floor(maximum*.5))
  local second: number?=nil;local secondScore=-math.huge
  for _,id in candidates do
   local d=distance[id];if not d or d<separation or excluded[id]then continue end
   local score=scores[id]-math.abs(scores[id]-scores[first])*.35+d/math.max(1,maximum)*8+hash(fieldSeed+269,id,0,0)*3
   if score>secondScore then second,secondScore=id,score end
  end
  if not second then
   for _,id in candidates do local d=distance[id];if d and not excluded[id]and (not second or d>distance[second])then second=id end end
  end
  if not second then
   local far=first;for _,id in candidates do if distance[id]>distance[far]then far=id end end
   first=far;distance=distances(tiles,neighbors,first)
   stamp+=1;excluded={};for _,id in disk(neighbors,first,2,marks,stamp,nil)do excluded[id]=true end
   for _,id in candidates do if not excluded[id]and (not second or distance[id]>distance[second])then second=id end end
  end
  if not second and count<=64 then
   -- Strictly capped tiny-world fallback: at most 64 local disks/candidate scans.
   -- Larger maps never perform this bounded pair search.
   for _,candidate in candidates do
    stamp+=1;excluded={};for _,id in disk(neighbors,candidate,2,marks,stamp,nil)do excluded[id]=true end
    for _,other in candidates do if not excluded[other]then first=candidate;second=other;break end end
    if second then distance=distances(tiles,neighbors,first);break end
   end
  end
  return first,second,distance
 end
 local first,second,distance=choose()
 for _=1,16 do
  if first and second then break end
  if not broaden()then break end
  first,second,distance=choose()
 end
 assert(first and second,'topology lacks separated playable starting regions')
 local starts={first :: number,second :: number};local startFood: {number}={};local startProduction: {number}={};local protected: {[number]: boolean}={};local workedPlots: {[number]: boolean}={};local expanded=false
 -- A requested terrain is bare: a feature on the tile is cleared too, with its resource (as a terrain change clears it).
 -- A new resource clears a feature that cannot keep it.
 local function change(id: number,terrain: string?,resource: string?)
  local tile=tiles[id]
  if terrain and tile.terrain~=terrain then tile.terrain=terrain;tile.resource=nil;tile.feature=nil;repairs+=1
  elseif terrain and tile.feature then tile.feature=nil;tile.resource=nil;repairs+=1 end
  if resource and tile.resource~=resource then tile.resource=resource;repairs+=1 end
  if not featureAllows(tile.feature,tile.resource)then tile.feature=nil;repairs+=1 end
 end
 -- Reserve both capitals' worked plots before resources are assessed. Capital
 -- separation makes these adjacent neighborhoods disjoint, and later repairs
 -- must preserve the same plot's food and production together.
 for _,start in starts do
  if (tiles[start].terrain~='Grassland' and tiles[start].terrain~='Plains') or tiles[start].feature then change(start,'Grassland',nil)end
 end
 for _,start in starts do
  local worked: number?=nil
  for _,id in neighbors[start]do
   if passable(tiles[id])and food(tiles[id])>=2 and production(tiles[id])>=1 then worked=id;break end
  end
  if not worked then
   for _,id in neighbors[start]do
    if tiles[id].terrain=='Grassland' and tiles[id].resource=='Wheat'then change(id,'Plains','Wheat');worked=id;break end
   end
  end
  if not worked then
   for _,id in neighbors[start]do
    if passable(tiles[id])and tiles[id].resource==nil then change(id,'Plains',nil);worked=id;break end
   end
  end
  if not worked then
   for _,id in neighbors[start]do
    if passable(tiles[id])then change(id,'Plains',nil);worked=id;break end
   end
  end
  assert(worked,'starting region has no worked plot')
  protected[worked]=true;workedPlots[worked]=true
 end
 for _,start in starts do
  stamp+=1;local ids=disk(neighbors,start,2,marks,stamp,tiles)
  local hasFood,hasIron,hasHorses,hasLuxury=false,false,false,false
  for _,id in ids do local resource=tiles[id].resource
   if resource and ((not hasFood and (resource=='Wheat' or resource=='Deer'))or(not hasIron and resource=='Iron')or(not hasHorses and resource=='Horses')or(not hasLuxury and (resource=='Gold' or resource=='Spices')))then protected[id]=true end
   hasFood=hasFood or resource=='Wheat' or resource=='Deer'
   hasIron=hasIron or resource=='Iron';hasHorses=hasHorses or resource=='Horses'
   hasLuxury=hasLuxury or resource=='Gold' or resource=='Spices'
  end
  local function place(kind: string,terrain: string,feature: string?)
   local selected: number?=nil
   -- An empty reserved Plains plot can host these compatible deposits without
   -- losing its combined yields. This matters when a tiny region has few sites.
   if kind=='Wheat' or kind=='Horses'then for _,id in ids do
    if workedPlots[id]and tiles[id].resource==nil and tiles[id].terrain=='Plains'then selected=id;break end
   end end
   if not selected then for _,id in ids do local t=tiles[id];if id~=start and not protected[id]and passable(t)and t.resource==nil and t.terrain==terrain and t.feature==feature then selected=id;break end end end
   if not selected then for _,id in ids do if id~=start and not protected[id]and passable(tiles[id])and tiles[id].resource==nil then selected=id;break end end end
   if not selected then for _,id in ids do if id~=start and passable(tiles[id])and not protected[id]then selected=id;break end end end
   if not selected then
    -- A tiny coast can have every reachable plot reserved. Open at most one
    -- local blocked site for this deposit, reached in two steps from the city.
    -- Prefer a mountain foothill to reclaiming water; never build a route.
    local frontier={start}
    for _,id in neighbors[start]do if passable(tiles[id])then table.insert(frontier,id)end end
    for _,blocked in {'Mountain','Water'}do
     for _,from in frontier do
      for _,id in neighbors[from]do
       if tiles[id].terrain==blocked then selected=id;break end
      end
      if selected then break end
     end
     if selected then break end
    end
    if selected then
     change(selected,terrain,kind);expanded=true
     stamp+=1;ids=disk(neighbors,start,2,marks,stamp,tiles)
    end
   end
   assert(selected,'starting region has no repair site')
   local site=tiles[selected]
   -- A matching site keeps its feature; any other site becomes bare terrain (then gains the wanted feature, except a
   -- reserved worked plot, which must keep the Plains food and production together).
   if workedPlots[selected]then change(selected,'Plains',kind)
   elseif site.terrain==terrain and site.feature==feature then change(selected,nil,kind)
   else change(selected,terrain,kind);if feature then site.feature=feature end end
   protected[selected]=true
  end
  if not hasFood then place('Wheat','Grassland')end
  if not hasIron then place('Iron','Hills')end
  if not hasHorses then place('Horses','Plains')end
  if not hasLuxury then place('Spices','Plains','Forest')end
  local f,p=0,0;for _,id in ids do f+=food(tiles[id]);p+=production(tiles[id])end
  -- Sparse polar/desert deployment areas need only a few fertile plots, never a path stripe.
  if f<8 then for _,id in ids do
   if id~=start and not protected[id]and passable(tiles[id])and tiles[id].resource==nil and food(tiles[id])==0 then change(id,'Grassland',nil);f+=3;if f>=8 then break end end
  end end
  if p<5 then for _,id in ids do
   if id~=start and not protected[id]and passable(tiles[id])and tiles[id].resource==nil and production(tiles[id])==0 then change(id,'Hills',nil);p+=2;if p>=5 then break end end
  end end
 end
 if expanded then
  biggest=components(tiles,neighbors)
  distance=distances(tiles,neighbors,starts[1])
 end
 -- Later strategic deposits (Saltpeter and Oil) settle in bare, unreserved land once both starting regions are final, so
 -- they never move a start or take a reserved plot: Oil in tundra and, where a second field is high, deserts and plains;
 -- Saltpeter in the other deserts and, where that field is low, hills and plains. Each start then gets one of each within four steps (and at least two from
 -- the capital, leaving its deployment ring as it was) when its region has none: on the nearest bare compatible site
 -- (Oil may also go on hills), else the nearest bare grassland (which becomes plains), else in place of the nearest
 -- unreserved featureless resource of a kind the region holds at least twice more (a deposit change, not a starting
 -- repair; a dense resource region can leave no bare land).
 local function bareSite(id: number): boolean
  local tile=tiles[id];return passable(tile)and tile.resource==nil and tile.feature==nil and not protected[id]and not workedPlots[id]and id~=starts[1]and id~=starts[2]
 end
 for id,tile in tiles do
  if deposit[id]<=.27 or not bareSite(id)then continue end
  local k=depositKind[id]
  if tile.terrain=='Tundra' or (tile.terrain=='Desert' and k>0)or(tile.terrain=='Plains' and k>.3)then tile.resource='Oil'
  elseif tile.terrain=='Desert' or (tile.terrain=='Hills' and k<-.05)or(tile.terrain=='Plains' and k<-.2)then tile.resource='Saltpeter' end
 end
 local depositTerrains: {[string]: {[string]: boolean}}={Saltpeter={Hills=true,Desert=true,Plains=true},Oil={Desert=true,Tundra=true,Plains=true,Hills=true}}
 for _,start in starts do
  stamp+=1;local ids=disk(neighbors,start,4,marks,stamp,tiles)
  for _,kind in {'Saltpeter','Oil'}do
   local present=false;for _,id in ids do if tiles[id].resource==kind then present=true;break end end
   if present then continue end
   local inner: {[number]: boolean}={[start]=true};for _,id in neighbors[start]do inner[id]=true end
   local held: {[string]: number}={};for _,id in ids do local r=tiles[id].resource;if r then held[r]=(held[r]or 0)+1 end end
   local site: number?=nil
   for pass=1,3 do
    for _,id in ids do
     local tile=tiles[id]
     if inner[id]then continue end
     local open=bareSite(id)
     if pass==3 then
      local r=tile.resource
      open=r~=nil and r~='Saltpeter' and r~='Oil' and (held[r]or 0)>=3
      if open then tile.resource=nil;open=bareSite(id);tile.resource=r end
     end
     if open and (depositTerrains[kind][tile.terrain]or (pass>=2 and tile.terrain=='Grassland'))then site=id;break end
    end
    if site then break end
   end
   if site then
    if tiles[site].terrain=='Grassland' then tiles[site].terrain='Plains' end
    tiles[site].resource=kind
   end
  end
 end
 -- Both regions may overlap on tiny worlds. Report the finished world, not a
 -- stale intermediate score from before the other region was repaired.
 for player,start in starts do
  stamp+=1;local ids=disk(neighbors,start,2,marks,stamp,tiles);local f,p=0,0
  for _,id in ids do f+=food(tiles[id]);p+=production(tiles[id])end
  startFood[player]=f;startProduction[player]=p
 end
 -- Rivers come last, from the finished terrain, so no later edit can strand one away from water. They change no
 -- starting-region food or production.
 local height: {number}={}
 for id,tile in tiles do height[id]=elevation[id]+(if tile.terrain=='Hills' then .05 else 0)end
 local rivers=carveRivers(tiles,neighbors,height,fieldSeed)
 local land,walkable,resources,featured,riverTiles=0,0,0,0,0
 for _,tile in tiles do
  if tile.terrain~='Water'then land+=1 end;if passable(tile)then walkable+=1 end;if tile.resource then resources+=1 end
  if tile.feature then featured+=1 end;if tile.river then riverTiles+=1 end
 end
 return {tiles=tiles,starts=starts,diagnostics={landFraction=land/count,passableFraction=walkable/count,largestPassableFraction=#biggest/math.max(1,walkable),startDistance=distance[second :: number],repairs=repairs,resourceFraction=resources/count,startFood=startFood,startProduction=startProduction,featureFraction=featured/count,rivers=rivers,riverFraction=riverTiles/count}}
end
return table.freeze(Generation)
