-- Test the addon lifecycle without loading Windows libraries on the host.
local script = assert(arg[1]);
for _, outcome in ipairs({1, -3, -4}) do
    local callbacks, installed, removed = {}, 0, 0;
    addon = {};
    AshitaCore = { GetInstallPath = function() return 'C:\\game'; end };
    ashita = { events = { register = function(_, name, fn) callbacks[name] = fn; end } };
    package.loaded.common = {};
    package.loaded.ffi = {
        cdef = function() end,
        C = {
            LoadLibraryA = function(path) assert(path == 'C:\\game\\addons\\targetguard\\targetguard.dll'); return 1; end,
            GetProcAddress = function(_, name)
                if name == 'TargetGuardInstall' then return function() installed = installed + 1; return outcome; end; end
                return function() removed = removed + 1; return 0; end;
            end,
        },
        cast = function(_, value) return value; end,
    };
    dofile(script);
    callbacks.targetguard_load(); callbacks.targetguard_unload();
    assert(installed == 1 and removed == 1);
end
print('PASS: addon load/unload and rejected-client reporting');
