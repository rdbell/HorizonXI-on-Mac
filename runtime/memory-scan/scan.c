/* Exact byte-pattern search. Each call reads current memory; no result cache. */
typedef unsigned char u8;
typedef unsigned int u32;
#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif
#if defined(__i386__) || defined(__x86_64__)
typedef char chars16 __attribute__((vector_size(16)));
typedef unsigned char bytes16 __attribute__((vector_size(16)));
#endif
static int hex(u8 c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
static int matches(const u8 *data, const u8 *value, const u8 *exact, u32 length) {
    for (u32 i = 0; i < length; i++)
        if (exact[i] && data[i] != value[i])
            return 0;
    return 1;
}
/* 1 = matched and offset written; 0 = no match; -1 = unsupported pattern. */
static int scan(const u8 *data, u32 size, const char *pattern, u32 pattern_size, u32 occurrence,
                u32 *offset) {
    if (!pattern || !pattern_size || (pattern_size & 1) || pattern_size > 512 || !offset)
        return -1;
    u8 value[256], exact[256];
    u32 length = pattern_size / 2, anchor = 0, literals = 0;
    for (u32 i = 0; i < length; i++) {
        u8 a = (u8)pattern[i * 2], b = (u8)pattern[i * 2 + 1];
        if (a == '?' && b == '?') {
            value[i] = 0;
            exact[i] = 0;
            continue;
        }
        int high = hex(a), low = hex(b);
        if (high < 0 || low < 0)
            return -1;
        value[i] = (u8)((high << 4) | low);
        exact[i] = 1;
        anchor = i;
        literals++;
    }
    if (!data || length > size)
        return 0;
    u32 count = size - length + 1;
    if (!literals) {
        if (occurrence >= count)
            return 0;
        *offset = occurrence;
        return 1;
    }
    u32 i = 0;
#if defined(__i386__) || defined(__x86_64__)
    bytes16 needle = {value[anchor], value[anchor], value[anchor], value[anchor],
                      value[anchor], value[anchor], value[anchor], value[anchor],
                      value[anchor], value[anchor], value[anchor], value[anchor],
                      value[anchor], value[anchor], value[anchor], value[anchor]};
    while (count - i >= 16) {
        /* Do not speculatively read another Windows page beyond an early match.
           A caller may pass a span containing an unreadable later page. */
        if (((__UINTPTR_TYPE__)(data + i + anchor) & 4095) > 4080) {
            if (data[i + anchor] == value[anchor] && matches(data + i, value, exact, length)) {
                if (!occurrence) {
                    *offset = i;
                    return 1;
                }
                occurrence--;
            }
            i++;
            continue;
        }
        bytes16 block;
        __builtin_memcpy(&block, data + i + anchor, 16);
        u32 mask = (u32)__builtin_ia32_pmovmskb128((chars16)(block == needle));
        while (mask) {
            u32 bit = (u32)__builtin_ctz(mask);
            mask &= mask - 1;
            u32 candidate = i + bit;
            if (matches(data + candidate, value, exact, length)) {
                if (!occurrence) {
                    *offset = candidate;
                    return 1;
                }
                occurrence--;
            }
        }
        i += 16;
    }
#endif
    for (; i < count; i++)
        if (data[i + anchor] == value[anchor] && matches(data + i, value, exact, length)) {
            if (!occurrence) {
                *offset = i;
                return 1;
            }
            occurrence--;
        }
    return 0;
}

/* Keep native access faults inside the helper, then let the original API handle
   the call through its normal binding. Lua protected calls do not catch SEH. */
EXPORT int ximac_scan(const u8 *data, u32 size, const char *pattern, u32 pattern_size,
                      u32 occurrence, u32 *offset) {
#if defined(_WIN32)
    __try {
        return scan(data, size, pattern, pattern_size, occurrence, offset);
    } __except (__exception_code() == 0xc0000005u ? 1 : 0) {
        return -1;
    }
#else
    return scan(data, size, pattern, pattern_size, occurrence, offset);
#endif
}
EXPORT u32 ximac_scan_version(void) { return 1; }
