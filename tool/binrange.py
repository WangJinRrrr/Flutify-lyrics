import re, sys
data = open(r'C:\Users\ZhaoYunFeng\AppData\Roaming\Spotify\Spotify.dll', 'rb').read()
start, end = int(sys.argv[1], 16), int(sys.argv[2], 16)
chunk = data[start:end]
# print printable runs with offsets
for m in re.finditer(rb'[\x20-\x7e]{2,}', chunk):
    print(hex(start + m.start()), m.group().decode())
