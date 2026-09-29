import sys
t=open(sys.argv[1],errors='ignore').read().split('\f')
for a in sys.argv[2:]:
    i=int(a); print(f"######## {sys.argv[1]} pdf page {i}"); print("\n".join(l for l in t[i-1].splitlines() if l.strip()))
