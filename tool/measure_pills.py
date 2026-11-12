# Precise measurement: find pill vertical extents by detecting the pill background
# (light gray ~#F0F0F2 on white background in light theme) in specific columns.
from PIL import Image

img = Image.open(
    r'C:\Users\ZhaoYunFeng\.cursor\projects\d-Flutify\assets\c__Users_ZhaoYunFeng_AppData_Roaming_Cursor_User_workspaceStorage_8ea33524c897ed778546244a1d7dd853_images_image-b1a74665-88f7-4564-9aa5-f7f8dc475332.png'
).convert('RGB')
w, h = img.size
px = img.load()


def runs_for(x, dark=False):
    """Vertical runs where pixel is pill-ish: slightly gray (unselected) or dark text area."""
    rows = []
    for y in range(h):
        r, g, b = px[x, y]
        # unselected pill bg: light gray, clearly darker than white bg but not text-dark
        if 225 < r < 250 and 225 < g < 250 and 225 < b < 252 and not (r > 245 and g > 245 and b > 245):
            rows.append(y)
    if not rows:
        return []
    runs = []
    start = prev = rows[0]
    for y in rows[1:]:
        if y > prev + 1:
            if prev - start >= 2:
                runs.append((start, prev, prev - start + 1))
            start = y
        prev = y
    if prev - start >= 2:
        runs.append((start, prev, prev - start + 1))
    return runs


print('sidebar columns:')
for x in range(20, 170, 5):
    r = runs_for(x)
    if r:
        print(' x=%d' % x, r)
print('home columns:')
for x in range(300, 500, 5):
    r = runs_for(x)
    if r:
        print(' x=%d' % x, r)
