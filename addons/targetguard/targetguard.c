/* Bound FFXI's fallback target traversal. Never bypass eligibility checks. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

typedef uintptr_t (__cdecl *selector_fn)(uintptr_t, uintptr_t, uintptr_t);
typedef struct { uintptr_t anchor; unsigned steps; } walk;
typedef struct { walk direction[2]; } thread_state;
static DWORD tls_index = TLS_OUT_OF_INDEXES;
static unsigned char *image;
static selector_fn selectors[2];
static volatile LONG trips;
static HMODULE own_module;
static const DWORD sites[4] = {0x157701,0x157718,0x15772f,0x157746};
static const DWORD targets[4] = {0x83950,0x83950,0x83b10,0x83b10};
static unsigned char saved[4][5], patches[4][5];
static const unsigned char entry[] = {0x53,0x56,0x8b,0xf1,0x57,0x85,0xf6,0x0f,0x84,0xc7,0,0,0};
#define WALK_LIMIT 2304u /* The client's entity lookup table has 0x900 entries. */

static void note_trip(void) {
    LONG count = InterlockedIncrement(&trips);
    if (count != 1 || !own_module) return;
    char path[MAX_PATH];
    DWORD n = GetModuleFileNameA(own_module,path,sizeof(path));
    if (!n || n >= sizeof(path)) return;
    char *slash = strrchr(path,'\\');
    if (!slash || (size_t)(slash-path)+17 >= sizeof(path)) return;
    strcpy(slash+1,"targetguard.log");
    HANDLE f = CreateFileA(path,FILE_APPEND_DATA,FILE_SHARE_READ,NULL,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if (f != INVALID_HANDLE_VALUE) {
        const char msg[] = "Prevented a repeated or over-budget target-selection walk.\r\n";
        DWORD written; WriteFile(f,msg,sizeof(msg)-1,&written,NULL); CloseHandle(f);
    }
}
static thread_state *state(void) {
    thread_state *s = TlsGetValue(tls_index);
    if (!s) {
        s = HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*s));
        if (s && !TlsSetValue(tls_index,s)) {HeapFree(GetProcessHeap(),0,s);s=NULL;}
    }
    return s;
}
static uintptr_t select_guarded(unsigned direction, int reset, uintptr_t previous, uintptr_t flags, uintptr_t extra) {
    thread_state *s = state();
    /* Fail closed if bookkeeping cannot be allocated: return no candidate. */
    if (!s) {note_trip(); return 0;}
    walk *w = &s->direction[direction];
    if (reset) {w->anchor=0;w->steps=0;}
    if (++w->steps > WALK_LIMIT) {note_trip();return 0;}
    uintptr_t next = selectors[direction](previous,flags,extra);
    if (reset) w->anchor=next;
    else if (next && (next==w->anchor || next==previous)) {note_trip();return 0;}
    return next;
}
static uintptr_t __cdecl first0(uintptr_t p,uintptr_t f,uintptr_t e){return select_guarded(0,1,p,f,e);}
static uintptr_t __cdecl next0 (uintptr_t p,uintptr_t f,uintptr_t e){return select_guarded(0,0,p,f,e);}
static uintptr_t __cdecl first1(uintptr_t p,uintptr_t f,uintptr_t e){return select_guarded(1,1,p,f,e);}
static uintptr_t __cdecl next1 (uintptr_t p,uintptr_t f,uintptr_t e){return select_guarded(1,0,p,f,e);}
static void call_bytes(unsigned char out[5],uintptr_t from,uintptr_t to){
    uint32_t delta=(uint32_t)(to-from-5);out[0]=0xe8;memcpy(out+1,&delta,4);
}
/* Called only from the game thread, between frames, never from a worker. */
static int install_module(unsigned char *base) {
    if (image) return image==base ? 1 : -1;
    if (!base) return -2;
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)base;
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return -3;
    IMAGE_NT_HEADERS32 *pe=(IMAGE_NT_HEADERS32*)(base+dos->e_lfanew);
    if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=IMAGE_FILE_MACHINE_I386 ||
       pe->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR32_MAGIC ||
       pe->FileHeader.TimeDateStamp!=1762938809u || pe->OptionalHeader.SizeOfImage!=12447744u)return -3;
    if(memcmp(base+0x1576a0,entry,sizeof(entry)))return -4;
    for(unsigned i=0;i<4;i++){
        call_bytes(saved[i],(uintptr_t)(base+sites[i]),(uintptr_t)(base+targets[i]));
        if(memcmp(base+sites[i],saved[i],5))return -4;
    }
    if(tls_index==TLS_OUT_OF_INDEXES){tls_index=TlsAlloc();if(tls_index==TLS_OUT_OF_INDEXES)return -5;}
    selector_fn wrappers[4]={first0,next0,first1,next1};
    for(unsigned i=0;i<4;i++)call_bytes(patches[i],(uintptr_t)(base+sites[i]),(uintptr_t)wrappers[i]);
    DWORD old;
    if(!VirtualProtect(base+0x1576a0,0xe0,PAGE_EXECUTE_READWRITE,&old))return -6;
    selectors[0]=(selector_fn)(base+targets[0]);selectors[1]=(selector_fn)(base+targets[2]);
    for(unsigned i=0;i<4;i++)memcpy(base+sites[i],patches[i],5);
    FlushInstructionCache(GetCurrentProcess(),base+0x1576a0,0xe0);
    DWORD unused;
    if(!VirtualProtect(base+0x1576a0,0xe0,old,&unused)){
        for(unsigned i=0;i<4;i++)memcpy(base+sites[i],saved[i],5);
        FlushInstructionCache(GetCurrentProcess(),base+0x1576a0,0xe0);
        VirtualProtect(base+0x1576a0,0xe0,old,&unused);return -6;
    }
    image=base;return 1;
}
__declspec(dllexport) int __cdecl TargetGuardInstall(void){return install_module((unsigned char*)GetModuleHandleA("FFXiMain.dll"));}
__declspec(dllexport) LONG __cdecl TargetGuardTrips(void){return trips;}
__declspec(dllexport) int __cdecl TargetGuardRemove(void){
    if(!image)return 0;
    for(unsigned i=0;i<4;i++)if(memcmp(image+sites[i],patches[i],5))return -4;
    DWORD old,unused;if(!VirtualProtect(image+0x1576a0,0xe0,PAGE_EXECUTE_READWRITE,&old))return -6;
    for(unsigned i=0;i<4;i++)memcpy(image+sites[i],saved[i],5);
    FlushInstructionCache(GetCurrentProcess(),image+0x1576a0,0xe0);
    int ok=VirtualProtect(image+0x1576a0,0xe0,old,&unused);image=NULL;return ok?1:-6;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID reserved){
    (void)reserved;
    if(reason==DLL_PROCESS_ATTACH)own_module=module;
    if(reason==DLL_THREAD_DETACH && tls_index!=TLS_OUT_OF_INDEXES){
        void *s=TlsGetValue(tls_index);if(s)HeapFree(GetProcessHeap(),0,s);
    }
    return TRUE;
}
