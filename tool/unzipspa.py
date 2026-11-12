import zipfile, os, sys
src = r'C:\Users\ZhaoYunFeng\AppData\Roaming\Spotify\Apps\xpui.spa'
dst = r'D:\tmp\xpui'
os.makedirs(dst, exist_ok=True)
with zipfile.ZipFile(src) as z:
    names = z.namelist()
    print(len(names), 'entries')
    for n in names[:40]:
        print(n)
    z.extractall(dst)
