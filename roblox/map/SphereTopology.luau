--!strict
-- Generated module-only Roblox form. Source: src/map/SphereTopology.luau
-- Source SHA-256: 4b71d3c4a6b0ccdebf126d30fd601086c7d14fd556365abfc96ced10b7d8be9c
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original frequency-subdivided icosahedron and its closed polygonal dual.
-- IDs follow fixed face traversal and integer barycentric vertex keys, never spatial rounding.
export type Vector = {read x: number, read y: number, read z: number}
export type Cell = {read id: number, read center: Vector, read corners: {Vector}, read neighbors: {number}}
export type Descriptor = {read frequency: number, read cells: {Cell}}
local SphereTopology = {}
local cache: {[number]: Descriptor} = {}
local cacheOrder: {number} = {}
local function normal(x: number, y: number, z: number): Vector
    local length=math.sqrt(x*x+y*y+z*z)
    return table.freeze({x=x/length,y=y/length,z=z/length})
end
local function dot(a: Vector,b: Vector): number return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a: Vector,b: Vector): Vector return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
local phi=(1+math.sqrt(5))/2
local vertices: {Vector}={normal(-1,phi,0),normal(1,phi,0),normal(-1,-phi,0),normal(1,-phi,0),normal(0,-1,phi),normal(0,1,phi),normal(0,-1,-phi),normal(0,1,-phi),normal(phi,0,-1),normal(phi,0,1),normal(-phi,0,-1),normal(-phi,0,1)}
local faces={{1,12,6},{1,6,2},{1,2,8},{1,8,11},{1,11,12},{2,6,10},{6,12,5},{12,11,3},{11,8,7},{8,2,9},{4,10,5},{4,5,3},{4,3,7},{4,7,9},{4,9,10},{5,10,6},{3,5,12},{7,3,11},{9,7,8},{10,9,2}}
function SphereTopology.generate(frequency: number): Descriptor
    assert(frequency==frequency and frequency%1==0 and frequency>=1 and frequency<=22,"sphere frequency must be 1..22")
    if cache[frequency] then return cache[frequency] end
    local centers: {Vector}, corners: {{Vector}}, adjacency: {{[number]: boolean}} = {},{},{}
    local index: {[string]: number}={}
    local function vertex(name: string, center: Vector): number
        local existing=index[name]; if existing then return existing end
        local id=#centers+1; index[name]=id; centers[id]=center; corners[id]={}; adjacency[id]={}; return id
    end
    for id,center in vertices do vertex("v"..id,center) end
    local function triangle(a: number,b: number,c: number)
        local first,second,third=centers[a],centers[b],centers[c]
        local ab={x=second.x-first.x,y=second.y-first.y,z=second.z-first.z}
        local ac={x=third.x-first.x,y=third.y-first.y,z=third.z-first.z}
        local n=cross(ab,ac); local sign=if dot(n,first)>0 then 1 else -1
        local corner=normal(n.x*sign,n.y*sign,n.z*sign)
        for _,id in {a,b,c} do table.insert(corners[id],corner) end
        adjacency[a][b]=true; adjacency[b][a]=true; adjacency[b][c]=true; adjacency[c][b]=true; adjacency[c][a]=true; adjacency[a][c]=true
    end
    for faceId,face in faces do
        local grid: {{number}}={}
        for i=0,frequency do
            grid[i+1]={}
            for j=0,frequency-i do
                local weights={frequency-i-j,i,j}
                local name: string=""
                local edge: {number}={}
                for k,w in weights do if w>0 then table.insert(edge,k) end end
                if #edge==1 then name="v"..face[edge[1]]
                elseif #edge==2 then
                    local a,b=face[edge[1]],face[edge[2]]
                    local weight=weights[edge[2]]
                    if a>b then a,b=b,a; weight=frequency-weight end
                    name="e"..a..":"..b..":"..weight
                else name="f"..faceId..":"..i..":"..j end
                local a,b,c=vertices[face[1]],vertices[face[2]],vertices[face[3]]
                grid[i+1][j+1]=vertex(name,normal(a.x*weights[1]+b.x*weights[2]+c.x*weights[3],a.y*weights[1]+b.y*weights[2]+c.y*weights[3],a.z*weights[1]+b.z*weights[2]+c.z*weights[3]))
            end
        end
        for i=0,frequency-1 do for j=0,frequency-i-1 do
            triangle(grid[i+1][j+1],grid[i+2][j+1],grid[i+1][j+2])
            if i+j<frequency-1 then triangle(grid[i+2][j+1],grid[i+2][j+2],grid[i+1][j+2]) end
        end end
    end
    local cells: {Cell}={}
    for id,center in centers do
        local axis: Vector=if math.abs(center.z)<0.9 then {x=0,y=0,z=1} else {x=0,y=1,z=0}
        local east=cross(axis,center); local north=cross(center,east)
        table.sort(corners[id],function(a: Vector,b: Vector): boolean return math.atan2(dot(a,north),dot(a,east))<math.atan2(dot(b,north),dot(b,east)) end)
        local neighbors: {number}={}; for other in adjacency[id] do table.insert(neighbors,other) end; table.sort(neighbors)
        cells[id]=table.freeze({id=id,center=center,corners=table.freeze(corners[id]),neighbors=table.freeze(neighbors)})
    end
    assert(#cells==10*frequency*frequency+2,"sphere vertex count")
    local result=table.freeze({frequency=frequency,cells=table.freeze(cells)})
    if #cacheOrder==2 then cache[table.remove(cacheOrder,1) :: number]=nil end
    cache[frequency]=result; table.insert(cacheOrder,frequency)
    return result
end
return table.freeze(SphereTopology)
