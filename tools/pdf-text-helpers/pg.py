import sys,re
t=open(sys.argv[1],errors='ignore').read().split('\f')
pat=re.compile(sys.argv[2],re.I)
for i,p in enumerate(t):
    for line in p.splitlines():
        if pat.search(line): print(f"pdfp{i+1}: {line.strip()[:150]}")
