--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original statistical/invariant tests for the original layered geography generator.
local Generator=require('../../src/map/WorldGeneration')
local Sphere=require('../../src/map/SphereTopology')
local Rules=require('../../src/simulation/BaseRules')
type Fixture={shape: 'Sphere'|'Hex',size: number,centers: {Generator.Center},neighbors: {{number}}}
local function sphere(frequency: number): Fixture
 local centers: {Generator.Center}={};local neighbors: {{number}}={}
 for _,cell in Sphere.generate(frequency).cells do centers[cell.id]=cell.center;neighbors[cell.id]=cell.neighbors end
 return {shape='Sphere',size=frequency,centers=centers,neighbors=neighbors}
end
local function hex(radius: number): Fixture
 local centers: {Generator.Center}={};local neighbors: {{number}}={};local coordinates: {{number}}={};local index: {[string]: number}={}
 for x=-radius,radius do for y=-radius,radius do if math.abs(x-y)<=radius then
  local id=#centers+1;centers[id]={x=(x-y/2)/radius,y=0,z=math.sqrt(3)*y/2/radius};coordinates[id]={x,y};index[x..':'..y]=id
 end end end
 for id,p in coordinates do
  neighbors[id]={};for _,offset in {{1,0},{0,1},{1,1},{-1,0},{0,-1},{-1,-1}}do
   local other=index[(p[1]+offset[1])..':'..(p[2]+offset[2])];if other then table.insert(neighbors[id],other)end
  end
  table.sort(neighbors[id])
 end
 return {shape='Hex',size=radius,centers=centers,neighbors=neighbors}
end
-- Resources by bare terrain, and by feature (woods are a feature on their own terrain since G4).
local compatible: {[string]: {[string]: boolean}}={Wheat={Grassland=true,Plains=true},Horses={Grassland=true,Plains=true},Iron={Hills=true},Gold={Hills=true,Desert=true},Spices={Plains=true},Deer={}}
local featureResources: {[string]: {[string]: boolean}}={Forest={Deer=true,Spices=true},Jungle={Spices=true},Marsh={},Oasis={}}
local allowed: {[string]: boolean}={Grassland=true,Plains=true,Hills=true,Mountain=true,Water=true,Desert=true,Tundra=true}
-- Natural food and production under the game rules, features included.
local function natural(tile: Generator.Tile): (number,number)
 local rule=Rules.terrains[tile.terrain];local feature=if tile.feature then Rules.features[tile.feature] else nil
 local f,p=rule.yields.food,rule.yields.production
 if feature and feature.overrideYields then f,p=feature.yields.food,feature.yields.production
 elseif feature then f+=feature.yields.food;p+=feature.yields.production end
 f,p=math.max(0,f),math.max(0,p)
 if tile.resource then local yields=Rules.resources[tile.resource].yields;f+=yields.food;p+=yields.production end
 return f,p
end
local featureTypes: {[string]: boolean}={}
local function passable(tile: Generator.Tile): boolean return tile.terrain~='Water' and tile.terrain~='Mountain'end
local function bfs(fixture: Fixture,tiles: {Generator.Tile},start: number,limit: number?): ({number},{number})
 local ids={start};local distances: {number}={[start]=0};local head=1
 while head<=#ids do local id=ids[head];head+=1
  if limit and distances[id]>=limit then continue end
  for _,other in fixture.neighbors[id]do if distances[other]==nil and passable(tiles[other])then distances[other]=distances[id]+1;table.insert(ids,other)end end
 end
 return ids,distances
end
local function identical(a: Generator.Result,b: Generator.Result): boolean
 if a.starts[1]~=b.starts[1]or a.starts[2]~=b.starts[2]then return false end
 for id,tile in a.tiles do local other=b.tiles[id];if tile.id~=other.id or tile.terrain~=other.terrain or tile.resource~=other.resource then return false end end
 return true
end
local resourceTypes: {[string]: boolean}={};local terrainTypes: {[string]: boolean}={}
local aggregate={maps=0,repairs=0,largeMaps=0,landCoherence=0,resourceEdges=0,resourceEdgesCount=0,mountainBorder=0,mountainCount=0,lakes=0,startsDifferent=0}
local function check(fixture: Fixture,seed: number): Generator.Result
 local result=Generator.generate(seed,fixture.centers,fixture.neighbors,fixture.shape);local tiles=result.tiles
 assert(#tiles==#fixture.centers and #result.starts==2,'stable complete tile IDs and two starts')
 local land,walkable,resourceCount=0,0,0
 for id,tile in tiles do
  assert(tile.id==id and allowed[tile.terrain],'stable ID and declared terrain')
  terrainTypes[tile.terrain]=true
  if tile.terrain~='Water'then land+=1 end;if passable(tile)then walkable+=1 end
  if tile.feature then assert(table.find(Rules.features[tile.feature].terrains,tile.terrain),'feature terrain compatibility');featureTypes[tile.feature]=true end
  if tile.resource then
   if tile.feature then assert(featureResources[tile.feature][tile.resource] and table.find(Rules.improvements[Rules.resources[tile.resource].improvement].terrains,tile.terrain),'resource feature compatibility')
   else assert(compatible[tile.resource]and compatible[tile.resource][tile.terrain],'resource terrain compatibility') end
   resourceTypes[tile.resource]=true;resourceCount+=1
  end
 end
 assert(land/#tiles>.3 and land/#tiles<(if #tiles<=20 then .96 else .91),'usable land and meaningful ocean')
 local reachable,distance=bfs(fixture,tiles,result.starts[1])
 assert(distance[result.starts[2]]and distance[result.starts[2]]>=3,'distinct city-separated starts on the same traversable mainland')
 assert(#reachable/math.max(1,walkable)>.5,'land-only actors can reach a substantial mainland')
 for player,start in result.starts do
  assert((tiles[start].terrain=='Plains' or tiles[start].terrain=='Grassland') and not tiles[start].feature,'fertile capital site')
  local deployment=0;for _,other in fixture.neighbors[start]do if passable(tiles[other])then deployment+=1 end end
  assert(deployment>=3,'three free passable unit deployment neighbors')
  local adjacentYield=false
  for _,id in fixture.neighbors[start]do if passable(tiles[id])then
   local f,p=natural(tiles[id])
   if f>=2 and p>=1 then adjacentYield=true end
  end end
  assert(adjacentYield,'same adjacent worked plot supports initial food and production')
  local localIds=bfs(fixture,tiles,start,2);local found: {[string]: boolean}={};local f,p=0,0
  for _,id in localIds do
   local tile=tiles[id];if tile.resource then found[tile.resource]=true end
   local tf,tp=natural(tile);f+=tf;p+=tp
  end
  assert(found.Wheat or found.Deer,'local renewable food resource')
  assert(found.Iron and found.Horses,'both strategic upgrade paths available locally')
  assert(found.Gold or found.Spices,'local luxury without mirrored identical terrain')
  assert(f>=5 and p>=4,'capital has food and production capacity')
  assert(result.diagnostics.startFood[player]==f and result.diagnostics.startProduction[player]==p,'diagnostics reflect final shared-region game yields')
 end
 aggregate.maps+=1;aggregate.repairs+=result.diagnostics.repairs
 local neighborSame,edges,mountainSupported,mountains,clustered,totalResources=0,0,0,0,0,0
 for id,tile in tiles do
  local supported=false;local resourceNeighbor=false
  for _,other in fixture.neighbors[id]do
   local adjacent=tiles[other]
   if other>id then edges+=1;if (tile.terrain=='Water')==(adjacent.terrain=='Water')then neighborSame+=1 end end
   if adjacent.terrain=='Hills' or adjacent.terrain=='Mountain'then supported=true end
   if tile.resource and adjacent.resource==tile.resource then resourceNeighbor=true end
  end
  if tile.terrain=='Mountain'then mountains+=1;if supported then mountainSupported+=1 end end
  if tile.resource then totalResources+=1;if resourceNeighbor then clustered+=1 end end
 end
 if #tiles>=331 then
  aggregate.largeMaps+=1;local fraction=land/#tiles;local independent=fraction*fraction+(1-fraction)*(1-fraction)
  local coherence=neighborSame/edges-independent
  assert(coherence>.12,'coasts form spatially connected regions rather than shuffled speckles')
  assert(result.diagnostics.repairs<=18,'starting repairs are a bounded local edit, not a route carving')
  aggregate.landCoherence+=coherence;aggregate.resourceEdges+=clustered;aggregate.resourceEdgesCount+=totalResources
  aggregate.mountainBorder+=mountainSupported;aggregate.mountainCount+=mountains
  -- Independent water components distinguish ocean from enclosed inland lakes.
  local seen: {[number]: boolean}={};local waterComponents: {{number}}={}
  for id,tile in tiles do if tile.terrain=='Water'and not seen[id]then
   local queue={id};seen[id]=true;local head=1
   while head<=#queue do local current=queue[head];head+=1
    for _,other in fixture.neighbors[current]do if not seen[other]and tiles[other].terrain=='Water'then seen[other]=true;table.insert(queue,other)end end
   end
   table.insert(waterComponents,queue)
  end end
  table.sort(waterComponents,function(a: {number},b: {number}): boolean return #a>#b end)
  for index=2,#waterComponents do local water=waterComponents[index];local boundary=false
   if fixture.shape=='Hex'then for _,id in water do if #fixture.neighbors[id]<6 then boundary=true;break end end end
   if not boundary and #water>=2 and #water<#tiles*.08 then aggregate.lakes+=1 end
  end
 end
 return result
end
local started=os.clock()
for _,fixture in {sphere(1),sphere(2),sphere(6),sphere(8),sphere(12),sphere(16),sphere(22),hex(3),hex(10),hex(15),hex(20),hex(30),hex(40)}do
 local landMin,landMax,componentMin,repairs=1,0,1,0
 for _,seed in {42,771,20261001,-17,918273,0}do
  local result=check(fixture,seed);landMin=math.min(landMin,result.diagnostics.landFraction);landMax=math.max(landMax,result.diagnostics.landFraction)
  componentMin=math.min(componentMin,result.diagnostics.largestPassableFraction);repairs+=result.diagnostics.repairs
  if seed==42 then assert(identical(result,Generator.generate(seed,fixture.centers,fixture.neighbors,fixture.shape)),'deterministic seeded fields and starts')end
 end
 print(string.format('%s %d (%d): land %.2f..%.2f; minimum mainland %.2f; mean local repairs %.1f',fixture.shape,fixture.size,#fixture.centers,landMin,landMax,componentMin,repairs/6))
end
-- Tiny frequency aliases are the hardest case: broad masks cannot assume dense sampling.
for seed=1,180 do
 local tinyOk,tinyErr=pcall(function()check(sphere(1),seed)end);assert(tinyOk,'Sphere frequency-one seed '..tostring(seed)..': '..tostring(tinyErr))
 local ok,err=pcall(function()check(sphere(2),seed*7919)end);assert(ok,'Sphere tiny seed '..tostring(seed*7919)..': '..tostring(err))
 ok,err=pcall(function()check(hex(3),-seed*3571)end);assert(ok,'Hex tiny seed '..tostring(-seed*3571)..': '..tostring(err))
end
check(sphere(2),76);check(hex(4),16)
-- Every passable neighbor held a protected deposit, leaving the second capital
-- without a single plot that could feed growth and produce a building together.
check(sphere(2),116784261)
for _,seed in {3789352366,7126244748,23867264156}do check(sphere(2),seed)end
check(hex(3),-67849)
check(hex(3),9586495911)
-- Independent 32-bit LCG samples the full seed range, unlike the small positive
-- and arithmetic seed fixtures above. All checks inspect final game-rule yields
-- and reachable resources after both starting regions have been repaired.
local randomSeed=246813579
local smallFixtures={sphere(2),hex(3),hex(4)}
for index=1,512 do
 randomSeed=(randomSeed*1664525+1013904223)%4294967296
 local seed=if index%2==0 then randomSeed else -randomSeed
 for _,small in smallFixtures do
  local ok,err=pcall(function()check(small,seed)end)
  assert(ok,small.shape..' size '..tostring(small.size)..' random seed '..tostring(seed)..': '..tostring(err))
 end
 if index%8==0 then check(sphere(1),seed)end
end
assert(aggregate.landCoherence/aggregate.largeMaps>.2,'coherent continent boundaries across seeds and sizes')
assert(aggregate.mountainBorder/math.max(1,aggregate.mountainCount)>.75,'mountains have adjacent range/foothill structure')
assert(aggregate.resourceEdges/math.max(1,aggregate.resourceEdgesCount)>.3,'resource deposits form neighboring compatible clusters')
assert(aggregate.lakes>0,'sample ensemble contains genuine enclosed inland lakes')
for terrain in allowed do assert(terrainTypes[terrain],'ensemble includes '..terrain)end
assert(not terrainTypes.Forest,'woods are a feature, not the legacy Forest terrain')
for _,feature in Rules.featureOrder do assert(featureTypes[feature],'ensemble includes '..feature)end
for resource in compatible do assert(resourceTypes[resource],'ensemble includes '..resource)end
local fixture=sphere(12);local a=Generator.generate(42,fixture.centers,fixture.neighbors,'Sphere');local b=Generator.generate(43,fixture.centers,fixture.neighbors,'Sphere')
local changed=0;for id,tile in a.tiles do if tile.terrain~=b.tiles[id].terrain then changed+=1 end end
assert(changed>#a.tiles*.12 and (a.starts[1]~=b.starts[1]or a.starts[2]~=b.starts[2]),'seed changes geography and starting locations')
assert(not pcall(function()Generator.generate(0/0,fixture.centers,fixture.neighbors,'Sphere')end),'nonfinite seed rejected')
assert(not pcall(function()Generator.generate(9007199254740992,fixture.centers,fixture.neighbors,'Sphere')end),'unsafe seed rejected')
assert(identical(Generator.generate(-9007199254740991,fixture.centers,fixture.neighbors,'Sphere'),Generator.generate(-9007199254740991,fixture.centers,fixture.neighbors,'Sphere')),'safe seed extreme deterministic')
print(string.format('Original geography passed %d maps in %.2fs; mean repairs %.2f, mountain support %.2f, clustered deposits %.2f, inland lakes %d',aggregate.maps,os.clock()-started,aggregate.repairs/aggregate.maps,aggregate.mountainBorder/math.max(1,aggregate.mountainCount),aggregate.resourceEdges/math.max(1,aggregate.resourceEdgesCount),aggregate.lakes))
