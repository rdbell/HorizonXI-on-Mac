"""Differential tests against a simple independent pattern search oracle."""
import ctypes as c,random,sys
lib=c.CDLL(sys.argv[1]);f=lib.ximac_scan
f.argtypes=[c.c_void_p,c.c_uint32,c.c_char_p,c.c_uint32,c.c_uint32,c.POINTER(c.c_uint32)];f.restype=c.c_int
rng=random.Random(32032);cases=0
for trial in range(8000):
 size=rng.randrange(0,600);n=rng.randrange(1,90)
 data=bytearray(rng.randrange(0,12) for _ in range(size));pattern=[None if rng.random()<.35 else rng.randrange(0,12) for _ in range(n)]
 if n<=size and trial%2:
  start=rng.randrange(size-n+1)
  for i,v in enumerate(pattern):
   if v is not None:data[start+i]=v
 text=''.join('??' if v is None else f'{v:02x}' for v in pattern).encode()
 expected=[i for i in range(max(0,size-n+1)) if all(v is None or data[i+j]==v for j,v in enumerate(pattern))]
 buf=c.create_string_buffer(bytes(data))
 for nth in [0,1,2,0xffffffff]:
  out=c.c_uint32(0xdeadbeef);status=f(buf,size,text,len(text),nth,c.byref(out))
  want=expected[nth] if nth<len(expected) else None
  assert status==int(want is not None),(trial,nth,status,want)
  assert out.value==(want if want is not None else 0xdeadbeef),(trial,nth,out.value,want)
  cases+=1
for text in [b'',b'0',b'F?',b'?F',b' 1',b'GG',b'00'*257]:
 out=c.c_uint32();buf=c.create_string_buffer(b'\x00'*600)
 assert f(buf,600,text,len(text),0,c.byref(out))==-1,text
# Adjacent and overlapping results, all-wildcard patterns, exact end and 16-byte tails.
for size in range(1,65):
 buf=c.create_string_buffer(bytes([0xaa])*size)
 for text in [b'AA',b'AAAA',b'????',b'AA??AA']:
  n=len(text)//2
  for nth in range(size+1):
   out=c.c_uint32(0xdeadbeef);status=f(buf,size,text,len(text),nth,c.byref(out));valid=n<=size and nth<=size-n
   assert status==int(valid)
   assert out.value==(nth if valid else 0xdeadbeef)
   cases+=1
print(f'PASS {cases} differential cases plus 7 unsupported patterns')
