#!/usr/bin/env python3
"""Resolve Aura Glass accents to Moyash's official Moga Neon releases."""

import json
import math
import os
import struct
import sys
from urllib.parse import unquote


VARIANTS = {
    "blue": ("Blue", "Moga-Neon-Blue.zip", "d193a5cf9a38478165c4a9f41fdacd18"),
    "teal": ("Cyan", "Moga-Neon-Cyan.zip", "e0a1ff78c6b6b9f7248873b70002a2ba"),
    "green": ("Green", "Moga-Neon-Green.zip", "25e9a0f4df1f2bd4b749d687c2810c63"),
    "yellow": ("Yellow", "Moga-Neon-Yellow.zip", "acef804aa6e3e61e04bd931030753c2b"),
    "orange": ("Orange", "Moga-Neon-Orange.zip", "0ccc899ec383367afee017d30b67e203"),
    "red": ("Red", "Moga-Neon-Red.zip", "b3745d8268a8e790bba2996438dd4f53"),
    "pink": ("Rose", "Moga-Neon-Rose.zip", "834fe75fa3c513cc418aad96cd4fafb8"),
    "purple": ("Purple", "Moga-Neon-Purple.zip", "6ec7f0cc041c2aca32561493dd002763"),
    "slate": ("Sky", "Moga-Neon-Sky.zip", "41d45aed9191f4f252fdc8c71878c3a0"),
}


def variant_for(accent):
    try:
        return VARIANTS[accent][0]
    except KeyError as exc:
        raise ValueError("unknown Aura Glass accent: %s" % accent) from exc


def resolve(accent, metadata_path):
    variant, archive, expected_md5 = VARIANTS.get(accent, (None, None, None))
    if variant is None:
        raise ValueError("unknown Aura Glass accent: %s" % accent)

    try:
        with open(metadata_path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        raise ValueError("could not read Moga source metadata: %s" % exc) from exc

    entries = [item for item in payload.get("files", [])
               if item.get("name") == archive and str(item.get("active")) == "1"]
    if len(entries) != 1:
        raise ValueError("Moga metadata has %d entries named %s; expected one"
                         % (len(entries), archive))
    entry = entries[0]
    if entry.get("md5sum") != expected_md5:
        raise ValueError("Moga release %s has an unexpected MD5" % archive)
    encoded_url = entry.get("url")
    if not encoded_url:
        raise ValueError("Moga release %s has no download URL" % archive)
    return variant, archive, expected_md5, unquote(encoded_url)


# Moga's busy cursors are either the ring alone (wait, watch, clock), which
# hides where a click lands, or a ring beside a pointer (progress), and seven
# of the nine variants draw that ring in a stock blue (0, 102, 255) whatever
# the pointer's colour. Both become one design: the pack's own pointer at
# full size, hotspot unchanged, with a small spinner off the middle of its
# straight top-right edge, drawn here in the pointer's border colour.
XCURSOR_IMAGE = 0xfffd0002
MARKER = ".aura-glass-spinner"
# The stamp's suffix changes with the design, so packs built to an older one
# are rebuilt.
DESIGN = "material-spinner-1 badges-1 round-1"
# Outer radius 0.195 of the frame keeps the spinner small beside a pointer
# 0.47 of the frame wide. The stroke is a third of the outer radius, the
# proportion of the Material spinner (4 of a 44 diameter, rounded up so it
# stays 2 px wide at size 32).
RING_OUTER = 0.195
RING_STROKE = 0.065
# The gap between the pointer's edge and the spinner: 2 px at size 32.
EDGE_GAP = 0.06
# A soft drop shadow to match the one under Moga's pointer.
SHADOW_Y = 0.02
SHADOW_BLUR = 0.04
SHADOW_ALPHA = 0.35
# The Material indeterminate spinner: the arc's head runs out from 15 to 270
# degrees, then its tail catches up, both on the fast-out-slow-in curve,
# while the whole arc turns clockwise. One cycle is 45 frames of 33 ms, close
# to Material's 1.5 s. The steady turn of 465 degrees a cycle plus the
# tail's 255 makes two full turns, so the last frame runs into the first.
FRAMES = 45
FRAME_MS = 33
ARC_MIN = 15
ARC_MAX = 270
TURN = 720 - (ARC_MAX - ARC_MIN)

# The drag-and-drop and help cursors carry a glossy candy badge (blue, green,
# orange) whatever the pointer's colour. They get the busy cursor's layout:
# the full pointer, and in the spinner's place a flat disc in the border
# colour with a glyph in the pointer's dark fill. The disc is a little larger
# than the spinner (0.22 against 0.195 of the frame), the least that keeps a
# 2 px glyph legible inside it at size 32.
BADGE_RADIUS = 0.22
# Glyphs are drawn on a disc of radius 1: lines are (x0, y0, x1, y1) with
# round caps, arcs (cx, cy, radius, start degrees, sweep degrees) running
# clockwise, dots (cx, cy, radius). The stroke is 0.13 of the disc either
# side of the line.
GLYPH_STROKE = 0.13
GLYPHS = {
    "copy": {"lines": [(-.5, 0, .5, 0), (0, -.5, 0, .5)]},
    "link": {"lines": [(-.38, .38, .38, -.38), (.38, -.38, -.06, -.38),
                       (.38, -.38, .38, .06)]},
    "menu": {"lines": [(-.45, -.36, .45, -.36), (-.45, 0, .45, 0),
                       (-.45, .36, .45, .36)]},
    "help": {"arcs": [(0, -.2, .28, 180, 270)],
             "lines": [(0, .08, 0, .2)],
             "dots": [(0, .5, .12)]},
    "no-drop": {"lines": [(-.36, -.36, .36, .36), (-.36, .36, .36, -.36)]},
}
# The stand-alone round cursors (xkill's X, what's-this, not-allowed) are
# glossy 3D balls unlike the rest of the set. They become the pointer's
# material: a flat disc in its dark fill with a border in the border colour,
# as thick as the pointer's (0.035 of the frame, 3 px at 96), and the glyph
# in the border colour. The hotspot stays in the middle, where Moga has it.
# The disc is 0.38 of the frame in radius, a little under Moga's 0.44, so it
# weighs about as much as the pointer does.
ROUND_RADIUS = 0.38
ROUND_BORDER = 0.035
ROUND_STROKE = 0.1
ROUND_GLYPHS = {
    "x": GLYPHS["no-drop"],
    "help": GLYPHS["help"],
    "forbidden": {"arcs": [(0, 0, .55, 0, 360)],
                  "lines": [(-.39, -.39, .39, .39)]},
}
ROUNDS = {
    "x": ("X_cursor", "x-cursor", "kill", "pirate"),
    "help": ("question_arrow", "whats_this"),
    "forbidden": ("circle", "crossed-circle", "crossed_circle"),
}
# Each badge cursor, by the names the pack ships it under. Files that are
# byte-identical copies of the first name (the hashed X11 names) go with it.
BADGES = {
    "copy": ("copy", "dnd-copy"),
    "link": ("alias", "dnd-link", "link"),
    "menu": ("context-menu",),
    "help": ("help", "dnd-ask", "left_ptr_help"),
    "no-drop": ("dnd-no-drop", "forbidden", "no-drop"),
}


def _images(data):
    """Yield (pixel offset, pixel count) for every image chunk."""
    if data[:4] != b"Xcur":
        return
    header, _, count = struct.unpack_from("<III", data, 4)
    for i in range(count):
        kind, _, pos = struct.unpack_from("<III", data, header + i * 12)
        if kind == XCURSOR_IMAGE:
            width, height = struct.unpack_from("<II", data, pos + 16)
            yield pos + 36, width * height


def border_color(path):
    """The most common fully opaque, saturated colour of a pointer."""
    with open(path, "rb") as handle:
        data = handle.read()
    counts = {}
    for start, pixels in _images(data):
        for o in range(start, start + pixels * 4, 4):
            b, g, r, a = data[o:o + 4]
            if a == 255 and max(r, g, b) - min(r, g, b) > 60:
                counts[(r, g, b)] = counts.get((r, g, b), 0) + 1
    if not counts:
        raise ValueError("no border colour found in %s" % path)
    return max(counts, key=counts.get)


def _chunks(data):
    """[(nominal size, delay, width, height, xhot, yhot, pixels)]."""
    out = []
    _, header, _, count = struct.unpack_from("<4sIII", data, 0)
    for i in range(count):
        kind, size, pos = struct.unpack_from("<III", data, header + i * 12)
        if kind == XCURSOR_IMAGE:
            w, h, xhot, yhot, delay = struct.unpack_from("<IIIII", data,
                                                         pos + 16)
            out.append((size, delay, w, h, xhot, yhot,
                        bytes(data[pos + 36:pos + 36 + w * h * 4])))
    return out


def _encode(chunks):
    toc = b""
    body = b""
    pos = 16 + 12 * len(chunks)
    for size, delay, w, h, xhot, yhot, px in chunks:
        toc += struct.pack("<III", XCURSOR_IMAGE, size, pos)
        chunk = struct.pack("<9I", 36, XCURSOR_IMAGE, size, 1, w, h, xhot,
                            yhot, delay) + px
        body += chunk
        pos += len(chunk)
    return (struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(chunks))
            + toc + body)


def _edge(w, h, px):
    """Middle point and outward normal of the pointer's top-right edge.

    The edge is the rightmost opaque pixel of each row between the tip and
    the right corner; a line is fitted to its middle 60 %, leaving out the
    rounded corners at both ends.
    """
    right = {}
    for y in range(h):
        for x in range(w - 1, -1, -1):
            if px[(y * w + x) * 4 + 3] > 128:
                right[y] = x
                break
    top = min(right)
    corner = max(right, key=lambda y: (right[y], -y))
    span = corner - top
    pts = [(right[y] + .5, y + .5) for y in right
           if top + span * .2 <= y <= corner - span * .2]
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    slope = (sum((p[0] - mx) * (p[1] - my) for p in pts)
             / sum((p[1] - my) ** 2 for p in pts))  # dx per dy
    length = math.hypot(1, slope)
    return (mx, my), (1 / length, -slope / length)


def _ease(u):
    """Material's fast-out-slow-in, cubic-bezier(0.4, 0, 0.2, 1)."""
    lo, hi = 0.0, 1.0
    for _ in range(30):
        s = (lo + hi) / 2
        x = 3 * (1 - s) ** 2 * s * 0.4 + 3 * (1 - s) * s * s * 0.2 + s ** 3
        lo, hi = (s, hi) if x < u else (lo, s)
    s = (lo + hi) / 2
    return 3 * (1 - s) * s * s + s ** 3


def _arc(frame):
    """(tail, sweep) in radians of the spinner at one frame."""
    u = frame / FRAMES
    grow = ARC_MAX - ARC_MIN
    if u < .5:
        tail, head = 0, ARC_MIN + grow * _ease(2 * u)
    else:
        tail, head = grow * _ease(2 * u - 1), ARC_MAX
    start = -90 + TURN * u + tail
    return math.radians(start), math.radians(head - tail)


def _distance(dx, dy, mid, tail, sweep, ends):
    rel = (math.atan2(dy, dx) - tail) % (2 * math.pi)
    if rel <= sweep:
        return abs(math.hypot(dx, dy) - mid)
    return min(math.hypot(dx - ex, dy - ey) for ex, ey in ends)


def _spinner(size, color, frame):
    """(side, premultiplied BGRA) of one spinner frame, centred."""
    outer = RING_OUTER * size
    half = RING_STROKE * size / 2
    mid = outer - half
    blur = SHADOW_BLUR * size
    drop = SHADOW_Y * size
    side = math.ceil(2 * (outer + blur + drop)) + 2
    c = side / 2
    tail, sweep = _arc(frame)
    ends = [(mid * math.cos(a), mid * math.sin(a)) for a in (tail, tail + sweep)]
    cr, cg, cb = color
    px = bytearray(side * side * 4)
    for y in range(side):
        for x in range(side):
            dx, dy = x + .5 - c, y + .5 - c
            cover = min(1.0, max(0.0, half - _distance(dx, dy, mid, tail,
                                                       sweep, ends) + .5))
            shade = _distance(dx, dy - drop, mid, tail, sweep, ends)
            shade = SHADOW_ALPHA * min(1.0, max(0.0, (half + blur - shade)
                                                / (2 * blur)))
            alpha = cover + shade * (1 - cover)
            if alpha:
                o = (y * side + x) * 4
                px[o:o + 4] = bytes((round(cb * cover), round(cg * cover),
                                     round(cr * cover), round(255 * alpha)))
    return side, px


def _over(dst, dw, src, sw, sh, ox, oy):
    """Premultiplied "over" of src at (ox, oy) onto dst, clipped."""
    for y in range(sh):
        ty = oy + y
        if not 0 <= ty < len(dst) // (dw * 4):
            continue
        for x in range(sw):
            s = (y * sw + x) * 4
            sa = src[s + 3]
            tx = ox + x
            if not sa or not 0 <= tx < dw:
                continue
            d = (ty * dw + tx) * 4
            for c in range(4):
                dst[d + c] = src[s + c] + dst[d + c] * (255 - sa) // 255


def _place(size, pw, ph, ppx, radius):
    """Centre of a mark off the top-right edge, and the frame shift it needs.

    Keep the pointer's frame where it is unless the mark runs off it; then
    shift the whole picture (and the hotspot) to bring the mark in, rather
    than cut it off.
    """
    (mx, my), (nx, ny) = _edge(pw, ph, ppx)
    reach = (EDGE_GAP + radius) * size
    rx, ry = mx + nx * reach, my + ny * reach
    extent = (radius + SHADOW_BLUR + SHADOW_Y) * size + 1
    sx = min(0, math.floor(rx - extent))
    sx = max(sx, math.ceil(rx + extent) - pw)
    sy = min(0, math.floor(ry - extent))
    sy = max(sy, math.ceil(ry + extent) - ph)
    return rx, ry, sx, sy


def _compose(pw, ph, ppx, mark, side, rx, ry, sx, sy):
    px = bytearray(pw * ph * 4)
    _over(px, pw, ppx, pw, ph, -sx, -sy)
    _over(px, pw, mark, side, side, round(rx - side / 2) - sx,
          round(ry - side / 2) - sy)
    return bytes(px)


def build_busy(pointer_data, color):
    """The busy cursor: full pointer plus a spinner off its top-right edge."""
    out = []
    for size, _, pw, ph, pxh, pyh, ppx in _chunks(pointer_data):
        rx, ry, sx, sy = _place(size, pw, ph, ppx, RING_OUTER)
        for frame in range(FRAMES):
            side, ring = _spinner(size, color, frame)
            out.append((size, FRAME_MS, pw, ph, pxh - sx, pyh - sy,
                        _compose(pw, ph, ppx, ring, side, rx, ry, sx, sy)))
    return _encode(out)


def _segment(px, py, x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    t = max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy)
                     / (dx * dx + dy * dy)))
    return math.hypot(px - x0 - t * dx, py - y0 - t * dy)


def _glyph_distance(px, py, glyph, stroke=GLYPH_STROKE):
    """Distance from (px, py), in disc units, to the glyph's strokes."""
    best = math.inf
    for line in glyph.get("lines", ()):
        best = min(best, _segment(px, py, *line) - stroke)
    for cx, cy, r, start, sweep in glyph.get("arcs", ()):
        tail, span = math.radians(start), math.radians(sweep)
        ends = [(r * math.cos(a), r * math.sin(a)) for a in (tail, tail + span)]
        best = min(best, _distance(px - cx, py - cy, r, tail, span, ends)
                   - stroke)
    for cx, cy, r in glyph.get("dots", ()):
        best = min(best, math.hypot(px - cx, py - cy) - r)
    return best


def _badge(size, color, ink, glyph):
    """(side, premultiplied BGRA) of one badge, centred."""
    radius = BADGE_RADIUS * size
    blur = SHADOW_BLUR * size
    drop = SHADOW_Y * size
    side = math.ceil(2 * (radius + blur + drop)) + 2
    c = side / 2
    px = bytearray(side * side * 4)
    for y in range(side):
        for x in range(side):
            dx, dy = x + .5 - c, y + .5 - c
            cover = min(1.0, max(0.0, radius - math.hypot(dx, dy) + .5))
            shade = math.hypot(dx, dy - drop)
            shade = SHADOW_ALPHA * min(1.0, max(0.0, (radius + blur - shade)
                                                / (2 * blur)))
            alpha = cover + shade * (1 - cover)
            if not alpha:
                continue
            mark = 0.0
            if cover:
                mark = min(1.0, max(0.0, .5 - _glyph_distance(
                    dx / radius, dy / radius, glyph) * radius))
            rgb = [cover * (fill * (1 - mark) + dark * mark)
                   for fill, dark in zip(color, ink)]
            o = (y * side + x) * 4
            px[o:o + 4] = bytes((round(rgb[2]), round(rgb[1]), round(rgb[0]),
                                 round(255 * alpha)))
    return side, px


def _ink(pointer_data):
    """The pointer's dark fill: the most common opaque grey."""
    counts = {}
    for chunk in _chunks(pointer_data):
        px = chunk[6]
        for o in range(0, len(px), 4):
            b, g, r, a = px[o:o + 4]
            if a == 255 and max(r, g, b) - min(r, g, b) < 12:
                counts[(r, g, b)] = counts.get((r, g, b), 0) + 1
    return max(counts, key=counts.get) if counts else (36, 36, 36)


def _round(size, color, ink, glyph):
    """Premultiplied BGRA of one round cursor filling a size-square frame."""
    radius = ROUND_RADIUS * size
    border = ROUND_BORDER * size
    blur = SHADOW_BLUR * size
    drop = SHADOW_Y * size
    c = size / 2
    px = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            dx, dy = x + .5 - c, y + .5 - c
            r = math.hypot(dx, dy)
            cover = min(1.0, max(0.0, radius - r + .5))
            shade = math.hypot(dx, dy - drop)
            shade = SHADOW_ALPHA * min(1.0, max(0.0, (radius + blur - shade)
                                                / (2 * blur)))
            alpha = cover + shade * (1 - cover)
            if not alpha:
                continue
            edge = min(1.0, max(0.0, r - (radius - border) + .5))
            mark = 0.0
            if cover:
                mark = min(1.0, max(0.0, .5 - _glyph_distance(
                    dx / radius, dy / radius, glyph, ROUND_STROKE) * radius))
            lit = max(edge, mark)
            rgb = [cover * (dark * (1 - lit) + fill * lit)
                   for fill, dark in zip(color, ink)]
            o = (y * size + x) * 4
            px[o:o + 4] = bytes((round(rgb[2]), round(rgb[1]), round(rgb[0]),
                                 round(255 * alpha)))
    return bytes(px)


def build_round(pointer_data, color, glyph):
    """A round cursor in the pointer's material, hotspot in the middle."""
    ink = _ink(pointer_data)
    out = []
    for size, delay, *_ in _chunks(pointer_data):
        out.append((size, delay, size, size, size // 2, size // 2,
                    _round(size, color, ink, ROUND_GLYPHS[glyph])))
    return _encode(out)


def build_badge(pointer_data, color, glyph):
    """A badge cursor: full pointer plus a glyph disc off its top-right edge."""
    ink = _ink(pointer_data)
    out = []
    for size, delay, pw, ph, pxh, pyh, ppx in _chunks(pointer_data):
        rx, ry, sx, sy = _place(size, pw, ph, ppx, BADGE_RADIUS)
        side, mark = _badge(size, color, ink, GLYPHS[glyph])
        out.append((size, delay, pw, ph, pxh - sx, pyh - sy,
                    _compose(pw, ph, ppx, mark, side, rx, ry, sx, sy)))
    return _encode(out)


def recolor(theme_dir):
    cursors = os.path.join(theme_dir, "cursors")
    marker = os.path.join(theme_dir, MARKER)
    color = border_color(os.path.join(cursors, "left_ptr"))
    stamp = "%02x%02x%02x %s" % (color + (DESIGN,))
    try:
        with open(marker, encoding="utf-8") as handle:
            if handle.read().strip() == stamp:
                return stamp
    except OSError:
        pass
    with open(os.path.join(cursors, "left_ptr"), "rb") as handle:
        busy = build_busy(handle.read(), color)
    # Every animated cursor in the pack is one of the two busy cursors, each
    # shipped as several identical copies under different names. Write the
    # spinner once, to wait, and link the other names to it: at 3 MB a copy
    # the copies would add up to 30 MB a pack.
    animated = []
    for name in sorted(os.listdir(cursors)):
        path = os.path.join(cursors, name)
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            if len(list(_images(handle.read()))) > 4:
                animated.append(name)
    if "wait" not in animated:
        raise ValueError("no animated wait cursor in %s" % cursors)
    with open(os.path.join(cursors, "wait"), "wb") as handle:
        handle.write(busy)
    for name in animated:
        if name != "wait":
            path = os.path.join(cursors, name)
            os.remove(path)
            os.symlink("wait", path)
    with open(os.path.join(cursors, "left_ptr"), "rb") as handle:
        pointer = handle.read()
    for glyph, names in BADGES.items():
        _write_group(cursors, names, build_badge(pointer, color, glyph))
    for glyph, names in ROUNDS.items():
        _write_group(cursors, names, build_round(pointer, color, glyph))
    with open(marker, "w", encoding="utf-8") as handle:
        handle.write(stamp + "\n")
    return stamp


def _write_group(cursors, names, data):
    """Write a cursor to its first shipped name and link the others to it."""
    present = [n for n in names if os.path.lexists(os.path.join(cursors, n))]
    files = [n for n in present
             if not os.path.islink(os.path.join(cursors, n))]
    if not files:
        return
    target = files[0]
    path = os.path.join(cursors, target)
    with open(path, "rb") as handle:
        original = handle.read()
    twins = set(present) - {target}
    for name in os.listdir(cursors):
        other = os.path.join(cursors, name)
        if name != target and not os.path.islink(other) \
                and os.path.isfile(other):
            with open(other, "rb") as handle:
                if handle.read() == original:
                    twins.add(name)
    with open(path, "wb") as handle:
        handle.write(data)
    for name in sorted(twins):
        other = os.path.join(cursors, name)
        if os.path.islink(other) and os.readlink(other) == target:
            continue
        os.remove(other)
        os.symlink(target, other)


def main(argv):
    if len(argv) == 3 and argv[1] == "variant":
        print(variant_for(argv[2]))
        return 0
    if len(argv) == 4 and argv[1] == "resolve":
        print("\t".join(resolve(argv[2], argv[3])))
        return 0
    if len(argv) == 3 and argv[1] == "recolor":
        print(recolor(argv[2]))
        return 0
    print("usage: moga_cursor.py variant ACCENT | resolve ACCENT METADATA_JSON"
          " | recolor THEME_DIR", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except ValueError as exc:
        print("moga_cursor: %s" % exc, file=sys.stderr)
        raise SystemExit(1)
