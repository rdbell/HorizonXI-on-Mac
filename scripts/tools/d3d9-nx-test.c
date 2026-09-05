/* Check D3D9's 32-bit execution policy in a fresh, isolated Wine process.
 * Build: i686-w64-mingw32-gcc -O2 -Wall -Wextra -o d3d9-nx-test.exe \
 *        scripts/tools/d3d9-nx-test.c -ld3d9
 * Run with expected flags 9 for the correction, or 2 with MTLD3D_ENFORCE_NX=0.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdlib.h>

typedef LONG (WINAPI *query_fn)(HANDLE, int, void *, ULONG, ULONG *);
typedef LONG (WINAPI *set_fn)(HANDLE, int, void *, ULONG);

int main(int argc, char **argv) {
    if (argc != 2) return 64;
    ULONG expected = (ULONG)strtoul(argv[1], NULL, 0);
    if (expected != 9 && expected != 2) return 64;
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    query_fn query = (query_fn)(void *)GetProcAddress(nt, "NtQueryInformationProcess");
    set_fn set = (set_fn)(void *)GetProcAddress(nt, "NtSetInformationProcess");
    if (!query || !set) return 1;
    ULONG flags = 2, size = 0;
    if (set(GetCurrentProcess(), 0x22, &flags, sizeof(flags)) != 0) return 2;
    if (query(GetCurrentProcess(), 0x22, &flags, sizeof(flags), &size) != 0 || flags != 2) return 3;
    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    if (!d3d) return 4;
    if (query(GetCurrentProcess(), 0x22, &flags, sizeof(flags), &size) != 0 || flags != expected) {
        fprintf(stderr, "after Direct3DCreate9: flags=%lu expected=%lu\n", flags, expected);
        return 5;
    }
    ULONG legacy = 2;
    LONG status = set(GetCurrentProcess(), 0x22, &legacy, sizeof(legacy));
    if (query(GetCurrentProcess(), 0x22, &flags, sizeof(flags), &size) != 0 || flags != expected) return 6;
    if (expected == 9 && status == 0) return 7;
    IDirect3D9_Release(d3d);
    printf("flags=%lu, later execute-everywhere request status=0x%08lx\n", flags, (ULONG)status);
    return 0;
}
