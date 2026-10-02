--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original independent closed dual-mesh invariants for all supported sphere presets.
local Sphere=require("../../src/map/SphereTopology")
local Sizes=require("../../src/map/MapSizes")
local function dot(a: Sphere.Vector,b: Sphere.Vector): number return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a: Sphere.Vector,b: Sphere.Vector): Sphere.Vector return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
for _,preset in Sizes.spherePresets do
    local world=Sphere.generate(preset.frequency); local cells=world.cells
    assert(#cells==preset.tileCount and table.isfrozen(world) and table.isfrozen(cells))
    local vertexIds: {[any]: number}={}; local incidence: {[number]: {number}}={}; local edges: {[string]: {number}}={}
    local pentagons,vertices,area,degreeSum=0,0,0,0
    for id,cell in cells do
        assert(cell.id==id and table.isfrozen(cell) and table.isfrozen(cell.center) and table.isfrozen(cell.corners) and table.isfrozen(cell.neighbors))
        assert(math.abs(dot(cell.center,cell.center)-1)<1e-12)
        assert(#cell.neighbors==#cell.corners and (#cell.corners==5 or #cell.corners==6))
        if #cell.corners==5 then pentagons+=1 end; degreeSum+=#cell.neighbors
        for _,other in cell.neighbors do assert(other~=id and table.find(cells[other].neighbors,id)) end
        local cornerIds: {number}={}
        for i,p in cell.corners do
            assert(table.isfrozen(p) and math.abs(dot(p,p)-1)<1e-12)
            if not vertexIds[p] then vertices+=1; vertexIds[p]=vertices; incidence[vertices]={} end
            local cornerId=vertexIds[p]; cornerIds[i]=cornerId; table.insert(incidence[cornerId],id)
            local q=cell.corners[i%#cell.corners+1]
            assert(dot(cross(p,q),cell.center)>0,"outward winding at "..id)
            -- Sum exact spherical triangle solid angles around each polygon center.
            area+=2*math.atan2(dot(cell.center,cross(p,q)),1+dot(cell.center,p)+dot(p,q)+dot(q,cell.center))
        end
        for i,a in cornerIds do
            local b=cornerIds[i%#cornerIds+1]; local key=tostring(math.min(a,b))..":"..tostring(math.max(a,b))
            edges[key]=edges[key] or {}; table.insert(edges[key],id)
        end
    end
    assert(pentagons==12 and vertices==20*preset.frequency*preset.frequency)
    assert(math.abs(area-4*math.pi)<1e-8,"entire globe must be covered exactly once")
    local edgeCount=0
    for _,owners in edges do
        edgeCount+=1; assert(#owners==2,"closed manifold edge")
        assert(table.find(cells[owners[1]].neighbors,owners[2]),"mesh edge must match graph adjacency")
    end
    assert(edgeCount==degreeSum/2 and vertices-edgeCount+#cells==2,"Euler characteristic")
    for corner,cornerId in vertexIds do
        local owners=incidence[cornerId]; assert(#owners==3)
        local first=dot(corner,cells[owners[1]].center)
        for _,id in owners do assert(math.abs(dot(corner,cells[id].center)-first)<1e-12,"spherical circumcenter") end
    end
    local reached={[1]=true}; local queue={1}; local head=1
    while head<=#queue do local id=queue[head]; head+=1; for _,other in cells[id].neighbors do if not reached[other] then reached[other]=true; table.insert(queue,other) end end end
    assert(#queue==#cells,"connected globe")
    local minY,maxY=1,-1; local opposite=false
    for _,cell in cells do minY=math.min(minY,cell.center.y); maxY=math.max(maxY,cell.center.y); if dot(cell.center,cells[1].center)<-1+1e-12 then opposite=true end end
    assert(minY<-0.8 and maxY>0.8 and opposite,"poles and antipodes")
    -- Evict the bounded generator cache, then verify stable IDs and coordinates.
    Sphere.generate(1); Sphere.generate(3)
    local rebuilt=Sphere.generate(preset.frequency)
    for id,cell in cells do
        local other=rebuilt.cells[id]; assert(dot(cell.center,other.center)>1-1e-12)
        for i,neighbor in cell.neighbors do assert(other.neighbors[i]==neighbor) end
        for i,corner in cell.corners do assert(dot(corner,other.corners[i])>1-1e-12) end
    end
    print(preset.name.." sphere closed "..#cells.." cells, 12 pentagons, area "..area)
end
for _,invalid in {0,-1,23,1.5,math.huge} do assert(not pcall(Sphere.generate,invalid)) end
