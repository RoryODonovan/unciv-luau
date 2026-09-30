--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Derived from Unciv by Yair Morgenstern and contributors.
-- Upstream: core/src/com/unciv/logic/map/HexMath.kt (HexCoord)
-- Revision: 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- https://github.com/yairm210/Unciv/blob/42939c6a2cf31aa76f44ffc033015ad12fece9f5/core/src/com/unciv/logic/map/HexMath.kt
local HexCoord = {}
export type Coord = { read x: number, read y: number }

local function int32(value: number)
    assert(value == value and value % 1 == 0 and value >= -2147483648 and value <= 2147483647,
        "HexCoord components must be signed 32-bit integers")
end

function HexCoord.of(x: number, y: number): Coord
    int32(x)
    int32(y)
    return table.freeze({ x = x, y = y })
end

HexCoord.Zero = HexCoord.of(0, 0)

function HexCoord.plus(coord: Coord, other: Coord): Coord
    return HexCoord.of(coord.x + other.x, coord.y + other.y)
end

function HexCoord.plusXY(coord: Coord, x: number, y: number): Coord
    return HexCoord.of(coord.x + x, coord.y + y)
end

function HexCoord.minus(coord: Coord, other: Coord): Coord
    return HexCoord.of(coord.x - other.x, coord.y - other.y)
end

function HexCoord.times(coord: Coord, multiplier: number): Coord
    int32(multiplier)
    return HexCoord.of(coord.x * multiplier, coord.y * multiplier)
end

function HexCoord.eq(coord: Coord, x: number, y: number): boolean
    return coord.x == x and coord.y == y
end

function HexCoord.equals(a: Coord, b: Coord): boolean
    return HexCoord.eq(a, b.x, b.y)
end

function HexCoord.cpy(coord: Coord): Coord
    return coord -- Immutable, matching upstream.
end

function HexCoord.toHexCoord(coord: Coord): Coord
    return coord
end

function HexCoord.toVector2(coord: Coord): Coord
    return { x = coord.x, y = coord.y }
end

function HexCoord.asSerializable(coord: Coord): Coord
    return { x = coord.x, y = coord.y }
end

function HexCoord.toPrettyString(coord: Coord): string
    return string.format("(%d,%d)", coord.x, coord.y)
end

function HexCoord.fromString(value: string): Coord
    local x, y = string.match(value, "^%(([+-]?%d+),([+-]?%d+)%)$")
    assert(x ~= nil and y ~= nil, "Invalid HexCoord representation")
    local nx, ny = tonumber(x), tonumber(y)
    assert(nx ~= nil and ny ~= nil, "Invalid HexCoord representation")
    return HexCoord.of(nx, ny)
end

return table.freeze(HexCoord)

