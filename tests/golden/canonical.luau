--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original canonical tree encoder and FNV-1a 64-bit hash for public engine regression fixtures.
local Canonical = {}

local function quote(value: string): string
    return '"' .. string.gsub(value, '[%z\1-\31\\"]', function(c: string): string
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        return string.format('\\u%04x', string.byte(c))
    end) .. '"'
end

-- JSON-shaped trees only. Dense positive-integer tables are arrays, all other tables are string-key objects.
-- An empty Luau table has no array/object identity: canonically encode every empty table as {}.
function Canonical.encode(value: any): string
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return if value then "true" else "false" end
    if kind == "string" then return quote(value) end
    if kind == "number" then
        assert(value == value and math.abs(value) < math.huge, "canonical numbers must be finite")
        -- Preserve every finite double exactly, with no rounding/tolerance or omitted gameplay fields.
        if value % 1 == 0 then return string.format("%.0f", if value == 0 then 0 else value) end
        return string.format("%.17g", value)
    end
    assert(kind == "table" and getmetatable(value) == nil, "canonical input must be a plain tree")
    local count, array = 0, true
    for key in value do
        count += 1
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then array = false end
    end
    local parts: {string} = {}
    if array and count > 0 then
        assert(#value == count, "canonical arrays must be dense")
        for index = 1, count do
            assert(value[index] ~= nil, "canonical arrays must be dense")
            table.insert(parts, Canonical.encode(value[index]))
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys: {string} = {}
    for key in value do
        assert(type(key) == "string", "canonical object keys must be strings")
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in keys do table.insert(parts, quote(key) .. ":" .. Canonical.encode(value[key])) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function Canonical.hashBytes(bytes: string): string
    -- Two 32-bit limbs: multiplication intermediates stay below 2^53 (Luau doubles are exact here).
    -- FNV offset cbf29ce484222325, prime 00000100000001b3; deliberately non-cryptographic.
    local high, low = 0xcbf29ce4, 0x84222325
    for index = 1, #bytes do
        low = bit32.bxor(low, string.byte(bytes, index))
        local product = low * 435
        high = (high * 435 + low * 256 + math.floor(product / 4294967296)) % 4294967296
        low = product % 4294967296
    end
    return string.format("%08x%08x", high, low)
end

function Canonical.hash(value: any): string return Canonical.hashBytes(Canonical.encode(value)) end
return table.freeze(Canonical)
