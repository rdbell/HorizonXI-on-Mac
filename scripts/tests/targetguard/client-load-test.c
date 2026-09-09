#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef int (__cdecl *action)(void);
int main(int argc,char **argv){
    if(argc!=3)return 2;
    HMODULE game=LoadLibraryA(argv[1]);if(!game){printf("Game load failed: %lu\n",GetLastError());return 3;}
    HMODULE guard=LoadLibraryA(argv[2]);if(!guard){printf("Guard load failed: %lu\n",GetLastError());return 4;}
    FARPROC proc=GetProcAddress(guard,"TargetGuardInstall");action install;memcpy(&install,&proc,sizeof(install));
    proc=GetProcAddress(guard,"TargetGuardRemove");action remove;memcpy(&remove,&proc,sizeof(remove));if(!install||!remove)return 5;
    unsigned char before[0xe0];memcpy(before,(char*)game+0x1576a0,sizeof(before));
    int a=install();printf("actual client install=%d\n",a);
    int b=remove();printf("actual client remove=%d\n",b);
    int same=!memcmp(before,(char*)game+0x1576a0,sizeof(before));printf("byte-exact rollback=%d\n",same);
    return a==1&&b==1&&same?0:6;
}
