typedef unsigned int u32;
typedef unsigned char u8;
__declspec(dllimport) int ximac_scan(const u8 *, u32, const char *, u32, u32, u32 *);
__declspec(dllimport) void *__stdcall VirtualAlloc(void *, u32, u32, u32);
__declspec(dllimport) int __stdcall VirtualProtect(void *, u32, u32, u32 *);
__declspec(dllimport) void __stdcall ExitProcess(u32);
__declspec(dllimport) void *__stdcall GetStdHandle(u32);
__declspec(dllimport) int __stdcall WriteFile(void *, const void *, u32, u32 *, void *);
static u32 random_state = 1234567;
static u32 next(void) {
    random_state = random_state * 1664525 + 1013904223;
    return random_state;
}
static void fail(u32 code) { ExitProcess(code); }
void mainCRTStartup(void) {
    u8 *memory = (u8 *)VirtualAlloc(0, 8192, 0x3000, 4);
    if (!memory)
        fail(2);
    u32 old;
    if (!VirtualProtect(memory + 4096, 4096, 1, &old))
        fail(3);
    char text[128];
    u8 values[64], wild[64];
    for (u32 trial = 0; trial < 12000; trial++) {
        u32 size = next() % 1024, length = next() % 64 + 1;
        u8 *data = memory + 4096 - size;
        for (u32 i = 0; i < size; i++)
            data[i] = (u8)(next() % 16);
        for (u32 i = 0; i < length; i++) {
            values[i] = (u8)(next() % 16);
            wild[i] = (u8)(next() % 3 == 0);
            if (wild[i]) {
                text[i * 2] = '?';
                text[i * 2 + 1] = '?';
            } else {
                text[i * 2] = '0';
                text[i * 2 + 1] = "0123456789ABCDEF"[values[i]];
            }
        }
        if (length <= size && trial % 2) {
            u32 at = next() % (size - length + 1);
            for (u32 i = 0; i < length; i++)
                if (!wild[i])
                    data[at + i] = values[i];
        }
        for (u32 nth = 0; nth < 3; nth++) {
            u32 expected = 0xdeadbeef, count = 0;
            if (length <= size)
                for (u32 i = 0; i <= size - length; i++) {
                    int same = 1;
                    for (u32 j = 0; j < length; j++)
                        if (!wild[j] && data[i + j] != values[j]) {
                            same = 0;
                            break;
                        }
                    if (same && count++ == nth) {
                        expected = i;
                        break;
                    }
                }
            u32 actual = 0xdeadbeef;
            int result = ximac_scan(data, size, text, length * 2, nth, &actual);
            if (actual != expected || result != (expected != 0xdeadbeef))
                fail(10);
        }
    }
    /* Early matches must not speculatively touch an inaccessible later page. */
    for (u32 length = 1; length <= 32; length++)
        for (u32 skew = 0; skew < 16; skew++) {
            u8 *data = memory + 4096 - 128 + skew;
            u32 count = 128 - skew;
            for (u32 i = 0; i < count; i++)
                data[i] = 0;
            for (u32 i = 0; i < length; i++) {
                data[count - length + i] = 0xa5;
                text[i * 2] = 'A';
                text[i * 2 + 1] = '5';
            }
            u32 actual = 0xdeadbeef;
            if (ximac_scan(data, count + 64, text, length * 2, 0, &actual) != 1 ||
                actual != count - length)
                fail(11);
        }
    u32 fault_result = 0xdeadbeef;
    if (ximac_scan(memory + 4096, 16, "AA", 2, 0, &fault_result) != -1)
        fail(12);
    if (ximac_scan(memory, 16, (const char *)1, 2, 0, &fault_result) != -1)
        fail(13);
    if (fault_result != 0xdeadbeef)
        fail(14);
    const char message[] = "PASS 36000 Windows x86 differential cases plus 512 early-match "
                           "guard-page cases and native fault fallback\n";
    u32 written;
    WriteFile(GetStdHandle((u32)-11), message, sizeof(message) - 1, &written, 0);
    ExitProcess(0);
}
