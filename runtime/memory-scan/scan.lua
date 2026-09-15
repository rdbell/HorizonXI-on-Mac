-- Shared Ashita memory search acceleration. Unsupported calls retain the original API.
return function(dll_path)
    local ffi = require('ffi');
    if not ffi.abi('32bit') or type(ashita) ~= 'table'
        or type(ashita.memory) ~= 'table' or type(ashita.memory.find) ~= 'function' then
        return false;
    end
    ffi.cdef[[
        unsigned int ximac_scan_version(void);
        int ximac_scan(const unsigned char*, unsigned int, const char*,
                       unsigned int, unsigned int, unsigned int*);
    ]];
    local native = ffi.load(dll_path);
    assert(native.ximac_scan_version() == 1, 'unsupported memory scanner ABI');
    local result = ffi.new('unsigned int[1]');
    local probe = ffi.new('unsigned char[4]', { 0x12, 0x34, 0x12, 0x34 });
    assert(native.ximac_scan(probe, 4, '12??', 4, 1, result) == 1 and result[0] == 2,
           'memory scanner self-check failed');

    local original = ashita.memory.find;
    local floor = math.floor;
    local function integer(value, low, high)
        return type(value) == 'number' and value == floor(value) and value >= low and value <= high;
    end
    local function fast(base, size, pattern, offset, count)
        if type(pattern) ~= 'string' or not integer(offset, -2147483648, 2147483647)
            or not integer(count, 0, 4294967295) then
            return nil;
        end
        if type(base) == 'string' then
            -- The original binding owns default-module aliases and size overrides.
            if base == '' or base:sub(1, 1) == ':' or base:find('\0', 1, true) or size ~= 0 then
                return nil;
            end
            local name = base;
            base = ashita.memory.get_base(name);
            size = ashita.memory.get_size(name);
            if not integer(base, 1, 4294967295) or not integer(size, 1, 4294967295) then
                return nil;
            end
        elseif not integer(base, 1, 4294967295) or not integer(size, 1, 4294967295) then
            return nil;
        end
        if base + size > 4294967295 then return nil; end
        local status = native.ximac_scan(ffi.cast('const unsigned char*', base), size,
                                        pattern, #pattern, count, result);
        if status < 0 then return nil; end
        if status == 0 then return 0; end
        return (base + tonumber(result[0]) + offset) % 4294967296;
    end
    local function find(...)
        if select('#', ...) == 5 then
            local answer = fast(...);
            if answer ~= nil then return answer; end
        end
        return original(...);
    end
    -- Publish only after loading, ABI validation, and the owned-buffer self-check.
    ashita.memory.find = find;
    if ashita.memory.findpattern == original then ashita.memory.findpattern = find; end
    return true;
end;
