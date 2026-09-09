#include "../../../addons/targetguard/targetguard.c"
#include <assert.h>
static unsigned mode;
static uintptr_t __cdecl mock(uintptr_t p,uintptr_t f,uintptr_t e){
    assert(f==17 && e==23);
    if(mode==0)return p<5?p+1:0;
    if(mode==1)return p==1?2:1;
    if(mode==2)return 1;
    if(mode==3)return p<3?p+1:2;
    return 0;
}
static selector_fn fixture_call(unsigned char *base,unsigned index){return (selector_fn)(base+sites[index]-12);}
static unsigned walk_test(unsigned char *base,unsigned direction,unsigned kind){
    mode=kind;selector_fn first=fixture_call(base,direction*2),next=fixture_call(base,direction*2+1);
    uintptr_t p=first(0,17,23);unsigned count=0;
    while(p){assert(++count<=WALK_LIMIT);p=next(p,17,23);}
    return count;
}
static DWORD WINAPI concurrent(LPVOID arg){
    unsigned char *base=arg;
    for(int i=0;i<100;i++){uintptr_t value=fixture_call(base,0)(0,17,23);unsigned count=0;while(value){assert(++count<=5);value=fixture_call(base,1)(value,17,23);}assert(count==5);}
    /* The test is an EXE, so its DllMain does not get thread-detach callbacks. */
    void *s=TlsGetValue(tls_index);if(s){HeapFree(GetProcessHeap(),0,s);TlsSetValue(tls_index,NULL);}
    return 0;
}
int main(void){
    unsigned char *base=VirtualAlloc(NULL,12447744,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);assert(base);
    IMAGE_DOS_HEADER *dos=(void*)base;dos->e_magic=IMAGE_DOS_SIGNATURE;dos->e_lfanew=0x100;
    IMAGE_NT_HEADERS32 *pe=(void*)(base+0x100);pe->Signature=IMAGE_NT_SIGNATURE;
    pe->FileHeader.Machine=IMAGE_FILE_MACHINE_I386;pe->FileHeader.TimeDateStamp=1762938809;
    pe->OptionalHeader.Magic=IMAGE_NT_OPTIONAL_HDR32_MAGIC;pe->OptionalHeader.SizeOfImage=12447744;
    memcpy(base+0x1576a0,entry,sizeof(entry));
    for(unsigned i=0;i<4;i++){
        unsigned char *s=base+sites[i];call_bytes(s,(uintptr_t)s,(uintptr_t)(base+targets[i]));
        /* A cdecl caller that forwards all three arguments through the patched CALL. */
        const unsigned char push[]={0xff,0x74,0x24,0x0c};
        for(int k=0;k<3;k++)memcpy(s-12+4*k,push,4);
        const unsigned char end[]={0x83,0xc4,0x0c,0xc3};memcpy(s+5,end,4);
    }
    for(unsigned i=0;i<2;i++){
        unsigned char *s=base+targets[i*2];call_bytes(s,(uintptr_t)s,(uintptr_t)mock);s[0]=0xe9;
    }
    unsigned char original[0xe0];memcpy(original,base+0x1576a0,sizeof(original));
    pe->FileHeader.TimeDateStamp++;assert(install_module(base)==-3);pe->FileHeader.TimeDateStamp--;
    assert(!memcmp(original,base+0x1576a0,sizeof(original)));
    base[sites[3]]^=1;assert(install_module(base)==-4);base[sites[3]]^=1;
    assert(!memcmp(original,base+0x1576a0,sizeof(original)));
    assert(install_module(base)==1);assert(install_module(base)==1);
    for(unsigned direction=0;direction<2;direction++){
        assert(walk_test(base,direction,0)==5); /* ordinary ordering */
        assert(walk_test(base,direction,1)==2); /* observed A/B cycle */
        assert(walk_test(base,direction,2)==1); /* self cycle */
        assert(walk_test(base,direction,3)==WALK_LIMIT); /* tail leading to a cycle */
        assert(walk_test(base,direction,4)==0); /* no candidates */
    }
    assert(TargetGuardTrips()==6);
    mode=0;HANDLE threads[4];for(int i=0;i<4;i++)threads[i]=CreateThread(NULL,0,concurrent,base,0,NULL);
    assert(WaitForMultipleObjects(4,threads,TRUE,10000)==WAIT_OBJECT_0);
    for(int i=0;i<4;i++){DWORD exit;GetExitCodeThread(threads[i],&exit);assert(exit==0);CloseHandle(threads[i]);}
    assert(TargetGuardRemove()==1);assert(TargetGuardRemove()==0);
    assert(!memcmp(original,base+0x1576a0,sizeof(original)));
    assert(install_module(base)==1);assert(TargetGuardRemove()==1);
    VirtualFree(base,0,MEM_RELEASE);
    puts("PASS: both patched directions, normal/no-candidate paths, A/B/self/tail cycles, thread isolation, build/signature rejection, idempotence and byte-exact rollback");return 0;
}
