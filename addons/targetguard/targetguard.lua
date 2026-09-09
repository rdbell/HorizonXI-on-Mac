-- Client compatibility fix; original target eligibility and actions are unchanged.
addon.name = 'targetguard';
addon.author = 'FFXI-on-Mac';
addon.version = '1.0.0';
addon.desc = 'Stops cyclic fallback target selection from freezing the client.';
jit.off();
require('common');
local ffi = require('ffi');
ffi.cdef[[
void* __stdcall LoadLibraryA(const char*);
void* __stdcall GetProcAddress(void*, const char*);
]];
-- Keep the DLL loaded for the process lifetime. The unload callback removes its hooks,
-- but a Lua reload must never leave a machine-code call pointing at an unloaded library.
local handle, install, remove;
local function report(message) print('[targetguard] ' .. message); end
ashita.events.register('load', 'targetguard_load', function()
    local path = AshitaCore:GetInstallPath() .. '\\addons\\targetguard\\targetguard.dll';
    handle = ffi.C.LoadLibraryA(path);
    if handle == nil then report('Could not load targetguard.dll; no patch applied.'); return; end
    local ip = ffi.C.GetProcAddress(handle, 'TargetGuardInstall');
    local rp = ffi.C.GetProcAddress(handle, 'TargetGuardRemove');
    if ip == nil or rp == nil then report('Invalid guard library; no patch applied.'); return; end
    install = ffi.cast('int (__cdecl *)(void)', ip);
    remove = ffi.cast('int (__cdecl *)(void)', rp);
    local result = install();
    if result == 1 then report('Target-cycle guard installed.');
    else report(('Not applied (code %d): unsupported client, modified code, or allocation failure.'):format(result)); end
end);
ashita.events.register('unload', 'targetguard_unload', function()
    if remove ~= nil then
        local result = remove();
        if result < 0 then report(('Could not restore original code (%d); restart the client.'):format(result)); end
    end
end);
