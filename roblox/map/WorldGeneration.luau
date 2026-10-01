--!strict
-- Generated module-only Roblox form. Source: src/map/WorldGeneration.luau
-- Source SHA-256: 4ac3a79467478a67c988e369af2b2f584c168f0ed5f0be7ac8352cb688506661
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original layered Cartesian geography and bounded graph-based starting regions.
-- This is a small civilization ruleset generator, not an Unciv map-generation port.
export type Center = {read x: number, read y: number, read z: number}
export type Tile = {id: number, terrain: string, resource: string?}
export type Diagnostics = {landFraction: number, passableFraction: number, largestPassableFraction: number, startDistance: number, repairs: number, resourceFraction: number, startFood: {number}, startProduction: {number}}
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
local function food(tile: Tile): number
 local base=if tile.terrain=='Grassland' then 3 elseif tile.terrain=='Plains' then 2 elseif tile.terrain=='Forest' or tile.terrain=='Hills' or tile.terrain=='Tundra' then 1 else 0
 return base+(if tile.resource=='Wheat' or tile.resource=='Deer' then 1 else 0)
end
local function production(tile: Tile): number
 local base=if tile.terrain=='Hills' or tile.terrain=='Forest'then 2 elseif tile.terrain=='Plains' or tile.terrain=='Desert'then 1 else 0
 return base+(if tile.resource=='Iron' or tile.resource=='Horses'then 1 else 0)
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
 local tiles: {Tile}={};local moisture: {number}={};local temperature: {number}={};local elevation: {number}={};local resourceField: {number}={};local resourceKind: {number}={}
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
  local terrain: string
  if land<0 or land>.22 and lake>.54 then terrain='Water'
  elseif ridge<.055 and belt>.04 and land>.04 then terrain='Mountain'
  elseif ridge<.18 and belt>-.3 then terrain='Hills'
  elseif heat<.24 then terrain='Tundra'
  elseif heat>.37 and wet<-.22 then terrain='Desert'
  elseif wet>.16 then terrain='Forest'
  elseif wet>-.04 then terrain='Grassland'
  else terrain='Plains'end
  tiles[id]={id=id,terrain=terrain}
  resourceField[id]=noise(fieldSeed+211,wx*5.4,wy*5.4,wz*5.4)
  resourceKind[id]=noise(fieldSeed+233,wx*3.1,wy*3.1,wz*3.1)
 end
 if count<=20 then
  -- The existing frequency-one toy globe has graph diameter three. Preserve one
  -- ocean tile and enough land for two nonoverlapping capital neighborhoods.
  local ocean=1;for id=2,count do if elevation[id]<elevation[ocean]then ocean=id end end
  for id,tile in tiles do
   if id==ocean then tile.terrain='Water'
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
  if resourceField[id]>.13 then
   local choose=resourceKind[id]
   if tile.terrain=='Hills'then tile.resource=if choose>0 then 'Iron' else 'Gold'
   elseif tile.terrain=='Forest'then tile.resource=if choose>-.04 and temperature[id]>.42 then 'Spices' else 'Deer'
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
  tiles[selected].resource=nil;repairs+=1;biggest=components(tiles,neighbors);return true
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
   local centerBonus=if tiles[id].terrain=='Grassland' or tiles[id].terrain=='Plains'then 5 else 0
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
 local function change(id: number,terrain: string?,resource: string?)
  local tile=tiles[id]
  if terrain and tile.terrain~=terrain then tile.terrain=terrain;tile.resource=nil;repairs+=1 end
  if resource and tile.resource~=resource then tile.resource=resource;repairs+=1 end
 end
 -- Reserve both capitals' worked plots before resources are assessed. Capital
 -- separation makes these adjacent neighborhoods disjoint, and later repairs
 -- must preserve the same plot's food and production together.
 for _,start in starts do
  if tiles[start].terrain~='Grassland' and tiles[start].terrain~='Plains'then change(start,'Grassland',nil)end
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
  local function place(kind: string,terrain: string)
   local selected: number?=nil
   -- An empty reserved Plains plot can host these compatible deposits without
   -- losing its combined yields. This matters when a tiny region has few sites.
   if kind=='Wheat' or kind=='Horses'then for _,id in ids do
    if workedPlots[id]and tiles[id].resource==nil and tiles[id].terrain=='Plains'then selected=id;break end
   end end
   if not selected then for _,id in ids do local t=tiles[id];if id~=start and not protected[id]and passable(t)and t.resource==nil and t.terrain==terrain then selected=id;break end end end
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
   assert(selected,'starting region has no repair site');change(selected,if workedPlots[selected]then 'Plains'else terrain,kind);protected[selected]=true
  end
  if not hasFood then place('Wheat','Grassland')end
  if not hasIron then place('Iron','Hills')end
  if not hasHorses then place('Horses','Plains')end
  if not hasLuxury then place('Spices','Forest')end
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
 -- Both regions may overlap on tiny worlds. Report the finished world, not a
 -- stale intermediate score from before the other region was repaired.
 for player,start in starts do
  stamp+=1;local ids=disk(neighbors,start,2,marks,stamp,tiles);local f,p=0,0
  for _,id in ids do f+=food(tiles[id]);p+=production(tiles[id])end
  startFood[player]=f;startProduction[player]=p
 end
 local land,walkable,resources=0,0,0
 for _,tile in tiles do if tile.terrain~='Water'then land+=1 end;if passable(tile)then walkable+=1 end;if tile.resource then resources+=1 end end
 return {tiles=tiles,starts=starts,diagnostics={landFraction=land/count,passableFraction=walkable/count,largestPassableFraction=#biggest/math.max(1,walkable),startDistance=distance[second :: number],repairs=repairs,resourceFraction=resources/count,startFood=startFood,startProduction=startProduction}}
end
return table.freeze(Generation)
