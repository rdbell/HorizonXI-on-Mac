-- Binding-contract tests. Native search correctness has independent differential tests.
local script = assert(arg[1], 'path to runtime/memory-scan/scan.lua required');
local calls, native_calls, lookup_calls = {}, 0, 0;
local answer, status, module_base = 9, 1, 1000;
local native = {
    ximac_scan_version = function() return 1; end,
    ximac_scan = function(base, size, pattern, length, count, out)
        if type(base) == 'table' then out[0] = 2; return 1; end
        native_calls = native_calls + 1;
        out[0] = answer;
        return status;
    end,
};
local ffi = {
    abi = function(name) return name == '32bit'; end,
    cdef = function() end,
    load = function() return native; end,
    new = function() return {}; end,
    cast = function(_, value) return value; end,
};
package.loaded.ffi = ffi;
local function original(...)
    calls[#calls + 1] = { n = select('#', ...), ... };
    return 8123, 'original-extra-return';
end
ashita = { memory = {
    find = original, findpattern = original,
    get_base = function() lookup_calls = lookup_calls + 1; return module_base; end,
    get_size = function() return 100; end,
} };
assert(dofile(script)('fixture.dll'));
local find = ashita.memory.find;
assert(find ~= original and ashita.memory.findpattern == find);
assert(find(1000, 100, 'AA', 0, 0) == 1009);
answer = 27;
assert(find(1000, 100, 'AA', -30, 0) == 997); -- Fresh result and signed offset.
assert(find(1000, 100, 'AA', 2147483647, 0) == 2147484674);
answer = 0;
assert(find(1, 10, 'AA', -2, 0) == 4294967295);
status = 0;
assert(find(1000, 100, 'AA', 123, 0) == 0); -- No offset on a failed search.
status = -1;
local value, extra = find(1000, 100, 'unsupported', 0, 0);
assert(value == 8123 and extra == 'original-extra-return');
status = 1;
answer = 3;
assert(find('module.dll', 0, 'AA', 0, 0) == 1003);
module_base = 2000;
assert(find('module.dll', 0, 'AA', 0, 0) == 2003 and lookup_calls == 2);

local function delegated(...)
    local expected, before = { n = select('#', ...), ... }, native_calls;
    local value, extra = find(...);
    assert(value == 8123 and extra == 'original-extra-return' and native_calls == before);
    local actual = calls[#calls];
    assert(actual.n == expected.n);
    for i = 1, expected.n do
        assert(actual[i] == expected[i] or (actual[i] ~= actual[i] and expected[i] ~= expected[i]));
    end
end
delegated(); delegated(1000, 100, 'AA', 0); delegated(1000, 100, 'AA', 0, 0, nil);
for _, base in ipairs({ 0, -1, 0.5, 4294967296, math.huge, 0/0, {}, true }) do
    delegated(base, 100, 'AA', 0, 0);
end
for _, size in ipairs({ 0, -1, 0.5, 4294967296, math.huge, 0/0, {}, true }) do
    delegated(1000, size, 'AA', 0, 0);
end
for _, name in ipairs({ '', ':boot', ':ffximain', 'module\0.dll' }) do
    delegated(name, 0, 'AA', 0, 0);
end
delegated('module.dll', 1, 'AA', 0, 0);
delegated(4294967290, 10, 'AA', 0, 0);
delegated(1000, 100, {}, 0, 0);
delegated(1000, 100, 'AA', -2147483649, 0);
delegated(1000, 100, 'AA', 2147483648, 0);
delegated(1000, 100, 'AA', nil, 0);
delegated(1000, 100, 'AA', 0, -1);
delegated(1000, 100, 'AA', 0, 4294967296);
delegated(1000, 100, 'AA', 0, nil);
module_base = 0;
delegated('missing.dll', 0, 'AA', 0, 0);

-- A load/self-check failure cannot publish a partially initialized wrapper.
ashita.memory.find = original;
local other_alias = function() return 99; end;
ashita.memory.findpattern = other_alias;
native.ximac_scan_version = function() return 2; end;
assert(not pcall(function() dofile(script)('wrong.dll'); end));
assert(ashita.memory.find == original and ashita.memory.findpattern == other_alias);
native.ximac_scan_version = function() return 1; end;
assert(dofile(script)('fixture.dll'));
assert(ashita.memory.findpattern == other_alias);
print('PASS memory scanner wrapper: fresh results, exact fallbacks, aliases, arithmetic, ABI failure');
