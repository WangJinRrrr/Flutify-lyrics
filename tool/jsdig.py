import re
data = open(r'D:\tmp\xpui\x\xpui.js', encoding='utf-8', errors='replace').read()
i = data.find('sdkId:h,transport:m.toPublic')
print('idx', i)
# find enclosing arrow/function start: search backwards for '=>' or 'function' near 'h' definition
seg = data[i-3000:i+200]
# look for h= definitions in this segment
for m in re.finditer(r'[,;{(]\s*h\s*=\s*[^,;{}()]{1,60}', seg):
    print('h-def:', m.group()[:80])
# print function signature before
j = seg.rfind('function')
print('---sig---')
print(seg[j:j+300])
k = seg.rfind('=>')
print('---arrow---')
print(seg[max(0,k-250):k+100])
