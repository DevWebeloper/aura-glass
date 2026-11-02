"""The tints the settings window suggests, chosen for how they look on the glass.

A tint is never seen as the colour it is written as. Each surface does something
different with it before it reaches the screen (GlassModel), and whatever comes
out sits in front of a blurred wallpaper. So a colour is judged here by what it
turns into on the surface it is for, never by its hex: the search moves the tint
until the *result* has the depth and the colour wanted, and text on it stays
readable.

All of the judging is in OKLab/OKLCH, where equal numbers look equal. In HSV a
blue and a yellow of one "value" are nowhere near one depth, which is why a row
built that way has one colour shouting and another gone to mud.

Standard library only, as preview_queue.py is, so it can be exercised without a
display. Decoding the picture and watching gsettings are the window's job
(WallpaperWatch in aura_glass_settings.py); this takes bytes and gives colours.
"""
import colorsys
import math
import os
import time
import xml.etree.ElementTree as ElementTree

# ---------- Colour spaces ----------


def _to_linear(channel):
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def _to_gamma(channel):
    if channel <= 0.0031308:
        return channel * 12.92
    return 1.055 * channel ** (1 / 2.4) - 0.055


def _cbrt(value):
    return value ** (1 / 3) if value >= 0 else -((-value) ** (1 / 3))


def rgb_to_oklab(rgb):
    """sRGB 0-1 to OKLab, with Björn Ottosson's published matrices."""
    red, green, blue = (_to_linear(channel) for channel in rgb)
    long_ = _cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    medium = _cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    short = _cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    return (0.2104542553 * long_ + 0.7936177850 * medium - 0.0040720468 * short,
            1.9779984951 * long_ - 2.4285922050 * medium + 0.4505937099 * short,
            0.0259040371 * long_ + 0.7827717662 * medium - 0.8086757660 * short)


def _oklab_to_linear(lab):
    lightness, a, b = lab
    long_ = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    medium = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    short = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * long_ - 3.3077115913 * medium + 0.2309699292 * short,
            -1.2684380046 * long_ + 2.6097574011 * medium - 0.3413193965 * short,
            -0.0041960863 * long_ - 0.7034186147 * medium + 1.7076147010 * short)


def _in_gamut(linear):
    return all(-0.0001 <= channel <= 1.0001 for channel in linear)


def oklch_to_rgb(lightness, chroma, hue):
    """OKLCH to sRGB, giving up chroma rather than hue to stay displayable.

    Clipping the channels instead turns a dark saturated blue into a different
    blue, and the harmony that hue was picked for goes with it.
    """
    radians = math.radians(hue)
    cos, sin = math.cos(radians), math.sin(radians)
    linear = _oklab_to_linear((lightness, chroma * cos, chroma * sin))
    if not _in_gamut(linear):
        low, high = 0.0, chroma
        for _step in range(12):
            middle = (low + high) / 2
            linear = _oklab_to_linear((lightness, middle * cos, middle * sin))
            if _in_gamut(linear):
                low = middle
            else:
                high = middle
        linear = _oklab_to_linear((lightness, low * cos, low * sin))
    return tuple(_to_gamma(min(1.0, max(0.0, channel))) for channel in linear)


def max_chroma(lightness, hue):
    """The most chroma sRGB can show of this hue at this lightness."""
    radians = math.radians(hue)
    cos, sin = math.cos(radians), math.sin(radians)
    low, high = 0.0, 0.4
    for _step in range(12):
        middle = (low + high) / 2
        if _in_gamut(_oklab_to_linear((lightness, middle * cos, middle * sin))):
            low = middle
        else:
            high = middle
    return low


def oklch_of(colour):
    """A #rrggbb colour as (lightness, chroma, hue)."""
    lab = rgb_to_oklab(rgb_of(colour))
    return lab[0], _chroma(lab), _hue(lab)


def _chroma(lab):
    return math.hypot(lab[1], lab[2])


def _hue(lab):
    return math.degrees(math.atan2(lab[2], lab[1])) % 360


def _hue_gap(first, second):
    return abs((first - second + 180) % 360 - 180)


def _distance(first, second):
    return math.dist(first, second)


def _luminance(rgb):
    red, green, blue = (_to_linear(channel) for channel in rgb)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def white_contrast(rgb):
    """The WCAG contrast of white text on this colour."""
    return 1.05 / (_luminance(rgb) + 0.05)


def hex_of(rgb):
    return "#%02x%02x%02x" % tuple(round(channel * 255) for channel in rgb)


def rgb_of(colour):
    return tuple(int(colour[index:index + 2], 16) / 255 for index in (1, 3, 5))


def _lerp(under, over, alpha):
    # In gamma space, because that is where Mutter and GTK composite and blur.
    return tuple(u + (o - u) * alpha for u, o in zip(under, over))


# ---------- What a surface does to a tint ----------

# The share of the theme's own colour that survives the app tint's mix, in
# percent. TOKEN_APP_TINT; tools/check-tokens.sh holds this to it.
APP_TINT_SHARE = 45

# @window_bg_color in the generated GTK sheet, which the app tint is mixed into.
WINDOW_GROUND = (0x22 / 255, 0x22 / 255, 0x26 / 255)

# The alpha of a dock and of a top bar over the desktop: rgba(0, 0, 0, 0.42) in
# css/shell-00-flat.css and PANEL_ALPHA in tools/apply-shell-tint.py.
FROSTED_DOCK_ALPHA = 0.42
SOLID_DOCK_ALPHA = 0.99

# What the shell tint keeps of a ground: tools/apply-shell-tint.py takes the
# tint's hue and saturation and leaves the lightness. Frosted is its 0.08 for a
# black ground, at the 0.42 of the floating surfaces; solid is rgba(22, 23, 27,
# 0.99), the commonest ground in css/shell-80-solid.css.
FROSTED_SHELL = (0.08, 0.42)
SOLID_SHELL = (0.096, 0.99)

# What a palette opened on a surface is tuning for, at the depth a suggestion
# rests at:
#
#   lightness  of the finished surface. The app's sits near the theme's own
#              ground (#222226 is 0.26), a touch up, because colour is hard to
#              see any darker: the same reason TINT shades stopped being all
#              near-black. Bars and the dock are seen against the desktop and
#              worn exactly, so they can carry much more.
#   chroma     of the finished surface. Past about 0.07 a whole window of it
#              stops reading as tinted glass and starts reading as a coloured
#              window. A bar is a strip, which can take more. The shell's is low
#              because that is all there is: its dark ground at 0.42 over a blur
#              moves about 0.03 at the very most.
#   contrast   for white text against the brightest part of the blur behind it.
#              7:1 on windows, because the dimmed labels are white at about half
#              alpha, so 7:1 is what leaves them at a readable 3:1 and more.
#              4.5:1 on a bar, whose text is all full white.
#
# None for lightness on the shell, which keeps its grounds' own whatever it is
# given, as tools/apply-shell-tint.py explains.
GOALS = {
    "all": (0.30, 0.048, 7.0),
    "app": (0.30, 0.048, 7.0),
    "shell": (None, 0.020, 4.5),
    "dock": (0.42, 0.088, 4.5),
    "panel": (0.42, 0.088, 4.5),
    "maximized": (0.34, 0.075, 4.5),
}

# A result with under this share of the chroma it was after is what grey glass
# looks like: its tint is fighting what is behind it and losing. Mostly a hue
# opposite the wallpaper, which is complementary on paper and cancels in a blur.
# Also where a surface's hue cannot move it far enough, which is the shell's limit.
MUDDY_SHARE = 0.6

# How far each step of depth moves a suggestion: lightness of the surface, and
# a share of its chroma.
DEPTH_LIGHTNESS = 0.045
DEPTH_CHROMA = 0.22

# Keeps a tint's own chroma displayable and off the neon end. Most of a surface's
# chroma comes from this one, so what a "goal" asks of it is well below this.
MAX_TINT_CHROMA = 0.17

# Yellow has no dark version: in OKLCH it passes through olive on the way down,
# which is the muddiest thing a window can be. Hues in this span come out at the
# warm end instead, as the bronze and old gold a dark yellow reads as anyway.
OLIVE_HUES = (86.0, 122.0)
OLIVE_RESCUE_HUE = 76.0


class GlassModel:
    """One surface: how it turns a tint into what is on screen.

    window_alpha is the live Opacity of the mode being edited, shade_alpha its
    maximized top bar, and solid that mode having no blur behind it. All three
    are read off the window's sliders, so what is judged is the glass as it is
    set right now.
    """

    def __init__(self, target, window_alpha=0.92, shade_alpha=0.6, solid=False):
        self.target = target
        self._window_alpha = window_alpha
        self._shade_alpha = shade_alpha
        self._dock_alpha = SOLID_DOCK_ALPHA if solid else FROSTED_DOCK_ALPHA
        self._shell = SOLID_SHELL if solid else FROSTED_SHELL

    def ground(self, tint):
        """What the surface paints, and at what alpha, given a tint."""
        if self.target in ("all", "app"):
            share = APP_TINT_SHARE / 100
            return _lerp(tint, WINDOW_GROUND, share), self._window_alpha
        if self.target == "shell":
            hue, _lightness, saturation = colorsys.rgb_to_hls(*tint)
            lightness, alpha = self._shell
            return colorsys.hls_to_rgb(hue, lightness, saturation), alpha
        if self.target == "maximized":
            return tint, self._shade_alpha
        return tint, self._dock_alpha

    def over(self, tint, backdrop):
        ground, alpha = self.ground(tint)
        return _lerp(backdrop, ground, alpha)


def _rescue_hue(hue):
    return OLIVE_RESCUE_HUE if OLIVE_HUES[0] <= hue <= OLIVE_HUES[1] else hue


def fit_tint(hue, model, backdrop, depth=0.0, vivid=1.0):
    """The tint of this hue that looks right on this surface over this blur.

    Returns (rgb, on-glass OKLab, reached), reached being the share of the
    chroma it was after that it got to. Numbers are searched for rather than worked out,
    because the composite is not a thing anyone can invert, and two rounds of
    bisection on chroma then lightness are plenty: the two barely interact at
    these chromas.

    Chroma is searched on how far the tint moves the surface toward its hue,
    against the same surface with a grey tint. Reading the result's chroma alone
    would call a tint done when the wallpaper showing through had already
    supplied that much, in some other colour.
    """
    goal_lightness, goal_chroma, min_contrast = GOALS[model.target]
    hue = _rescue_hue(hue)
    goal_chroma *= vivid * (1 + depth * DEPTH_CHROMA)
    radians = math.radians(hue)
    towards = (math.cos(radians), math.sin(radians))

    def result(lightness, chroma):
        tint = oklch_to_rgb(lightness, chroma, hue)
        lab = rgb_to_oklab(model.over(tint, backdrop.mean))
        grey = rgb_to_oklab(model.over(oklch_to_rgb(lightness, 0.0, hue),
                                       backdrop.mean))
        push = (lab[1] - grey[1]) * towards[0] + (lab[2] - grey[2]) * towards[1]
        return tint, lab, push

    def legible(tint):
        return white_contrast(model.over(tint, backdrop.brightest)) >= min_contrast

    # A mid value for the shell, whose lightness is only ever a way of holding
    # the saturation it keeps, and mid is where a hue can hold the most of it.
    lightness = 0.45 if goal_lightness is None else 0.25
    chroma = MAX_TINT_CHROMA / 2
    for _round in range(2):
        low, high = 0.005, MAX_TINT_CHROMA
        for _step in range(6):
            chroma = (low + high) / 2
            if result(lightness, chroma)[2] < goal_chroma:
                low = chroma
            else:
                high = chroma
        if goal_lightness is None:
            break
        low, high = 0.1, 0.78
        wanted = goal_lightness + depth * DEPTH_LIGHTNESS
        for _step in range(6):
            lightness = (low + high) / 2
            tint, lab, _push = result(lightness, chroma)
            if lab[0] < wanted and legible(tint):
                low = lightness
            else:
                high = lightness
        lightness = low

    tint, lab, push = result(lightness, chroma)
    # Against what this hue can hold at this depth: a dark teal has little chroma
    # to give in sRGB at all, which is a quiet colour and not a muddy one.
    possible = min(goal_chroma, result(lightness, MAX_TINT_CHROMA)[2])
    return tint, lab, min(1.0, min(push, _chroma(lab)) / possible)


# ---------- What is in the picture ----------

# Pixels past these are what a wallpaper's shadows and highlights are made of.
# They have no colour worth naming, however many of them there are.
MIN_LIGHTNESS = 0.16
MAX_LIGHTNESS = 0.94
# Under this a pixel is a grey to the eye, whichever way its channels lean.
MIN_CHROMA = 0.028

# OKLab bins, wide enough to merge a gradient's neighbours into one count. The
# weight on lightness is low when clustering because the tint's lightness is
# chosen by the surface, so two clusters of a hue differing only in lightness
# would come out as one suggestion anyway.
BIN_LIGHTNESS = 0.08
BIN_CHROMA = 0.024
CLUSTER_LIGHTNESS_WEIGHT = 0.35
CLUSTERS = 12
CLUSTER_ROUNDS = 6

# Two suggestions closer than this in hue are the same suggestion once a surface
# has been through them both.
MIN_HUE_GAP = 22.0

# The grid of a wallpaper's averages, which is what a blur leaves of it. Wide
# because it is a screen.
BACKDROP_COLUMNS = 6
BACKDROP_ROWS = 4

# What a swatch shows and a tint is judged over with no picture to go on: the
# stand-in wallpaper of TintScene, in the same bright, many-coloured spirit.
FALLBACK_BACKDROP = (
    ((0.33, 0.45, 0.72), (0.44, 0.50, 0.68), (0.55, 0.55, 0.64)),
    ((0.42, 0.47, 0.66), (0.55, 0.55, 0.60), (0.68, 0.54, 0.54)),
    ((0.55, 0.55, 0.60), (0.68, 0.54, 0.52), (0.80, 0.52, 0.45)),
)


class Backdrop:
    """A wallpaper as a blur leaves it: a grid of averages, and two summaries.

    brightest is what legibility is judged against, because that is the part of
    the wallpaper a window can be dragged over. mean is what colour is judged
    against, because a colour is judged across a whole surface.
    """

    def __init__(self, grid):
        self.grid = grid
        cells = [cell for row in grid for cell in row]
        self.mean = tuple(sum(cell[channel] for cell in cells) / len(cells)
                          for channel in range(3))
        self.brightest = max(cells, key=_luminance)


FALLBACK = Backdrop(FALLBACK_BACKDROP)


class Analysis:
    """What the picker needs from a wallpaper. Plain data: made off the UI thread."""

    def __init__(self, backdrop, hues):
        self.backdrop = backdrop
        # (hue, how vivid the picture is about it), most telling first.
        self.hues = hues
        lab = rgb_to_oklab(backdrop.mean)
        # The wallpaper's overall cast, when it has one to speak of.
        self.cast = _hue(lab) if _chroma(lab) >= 0.008 else None


def analyse_pixels(pixels, width, height, rowstride, channels):
    """Turn decoded RGB(A) rows into an Analysis. Deterministic, for one picture."""
    bins = {}
    totals = [[[0.0, 0.0, 0.0, 0] for _c in range(BACKDROP_COLUMNS)]
              for _r in range(BACKDROP_ROWS)]
    for y in range(height):
        start = y * rowstride
        block_row = totals[y * BACKDROP_ROWS // height]
        for x in range(width):
            offset = start + x * channels
            rgb = (pixels[offset] / 255, pixels[offset + 1] / 255,
                   pixels[offset + 2] / 255)
            cell = block_row[x * BACKDROP_COLUMNS // width]
            cell[0] += rgb[0]
            cell[1] += rgb[1]
            cell[2] += rgb[2]
            cell[3] += 1

            lab = rgb_to_oklab(rgb)
            if not MIN_LIGHTNESS <= lab[0] <= MAX_LIGHTNESS \
                    or _chroma(lab) < MIN_CHROMA:
                continue
            key = (round(lab[0] / BIN_LIGHTNESS), round(lab[1] / BIN_CHROMA),
                   round(lab[2] / BIN_CHROMA))
            held = bins.setdefault(key, [0.0, 0.0, 0.0, 0])
            held[0] += lab[0]
            held[1] += lab[1]
            held[2] += lab[2]
            held[3] += 1

    grid = tuple(tuple((cell[0] / cell[3], cell[1] / cell[3], cell[2] / cell[3])
                       if cell[3] else (0.0, 0.0, 0.0) for cell in row)
                 for row in totals)
    points = [((held[0] / held[3], held[1] / held[3], held[2] / held[3]), held[3])
              for held in bins.values()]
    return Analysis(Backdrop(grid), _telling_hues(points, width * height))


def analyse_colours(colours):
    """The same for a background with no picture: its one or two colours."""
    points = []
    for colour in colours:
        lab = rgb_to_oklab(colour)
        if MIN_LIGHTNESS <= lab[0] <= MAX_LIGHTNESS and _chroma(lab) >= MIN_CHROMA:
            points.append((lab, 1))
    first = colours[0]
    last = colours[-1]
    grid = tuple(tuple(_lerp(first, last, row / (BACKDROP_ROWS - 1))
                       for _column in range(BACKDROP_COLUMNS))
                 for row in range(BACKDROP_ROWS))
    return Analysis(Backdrop(grid), _telling_hues(points, max(1, len(points))))


def _cluster_distance(first, second):
    return math.hypot((first[0] - second[0]) * CLUSTER_LIGHTNESS_WEIGHT,
                      first[1] - second[1], first[2] - second[2])


def _telling_hues(points, total):
    """Cluster the pixels, and rank the clusters for colour rather than for area.

    Plain frequency is how a photo of a beach at dusk suggests eight sandy
    greys. Farthest-first seeding gives a small vivid region a centre of its
    own however few pixels it has, the square root stops the biggest area from
    winning outright, and chroma counts for as much as area does.
    """
    if not points:
        return []
    points.sort(key=lambda point: (-point[1], point[0]))
    centres = [points[0][0]]
    while len(centres) < min(CLUSTERS, len(points)):
        centres.append(max(points, key=lambda point: min(
            _cluster_distance(point[0], centre) for centre in centres))[0])

    for _round in range(CLUSTER_ROUNDS):
        members = [[0.0, 0.0, 0.0, 0] for _c in centres]
        for lab, weight in points:
            nearest = min(range(len(centres)), key=lambda index: _cluster_distance(
                lab, centres[index]))
            held = members[nearest]
            held[0] += lab[0] * weight
            held[1] += lab[1] * weight
            held[2] += lab[2] * weight
            held[3] += weight
        centres = [(held[0] / held[3], held[1] / held[3], held[2] / held[3])
                   if held[3] else centre for held, centre in zip(members, centres)]

    ranked = []
    for centre, held in zip(centres, members):
        if not held[3]:
            continue
        chroma = _chroma(centre)
        if chroma < MIN_CHROMA:
            continue
        score = math.sqrt(held[3] / total) * min(chroma, 0.16)
        ranked.append((score, _rescue_hue(_hue(centre)), chroma))
    ranked.sort(key=lambda found: (-found[0], found[1]))

    hues = []
    for _score, hue, chroma in ranked:
        if all(_hue_gap(hue, kept) >= MIN_HUE_GAP for kept, _vivid in hues):
            # Follows the picture: pastels suggest quiet tints and a poster
            # suggests strong ones, within what still reads as glass.
            hues.append((hue, min(1.2, max(0.72, 0.6 + chroma * 3.5))))
    return hues


# ---------- Finding the picture ----------

def slideshow_frame(path, now=None):
    """The file an XML background slideshow is showing, or None.

    A slideshow is a loop of <static> and <transition> entries from a
    <starttime>. A file can list <size> children, and the largest is the one
    closest to what is on screen.
    """
    try:
        root = ElementTree.parse(path).getroot()
    except (ElementTree.ParseError, OSError):
        return None

    def file_of(element):
        if element is None:
            return None
        sizes = element.findall("size")
        if sizes:
            def area(size):
                return int(size.get("width", 0)) * int(size.get("height", 0))
            element = max(sizes, key=area)
        text = (element.text or "").strip()
        if not text:
            return None
        return text if os.path.isabs(text) \
            else os.path.join(os.path.dirname(path), text)

    entries = []
    for entry in root:
        try:
            duration = float(entry.findtext("duration", ""))
        except ValueError:
            continue
        if entry.tag == "static":
            entries.append((duration, file_of(entry.find("file"))))
        elif entry.tag == "transition":
            # The picture it is fading to: that is the one about to be looked at.
            entries.append((duration, file_of(entry.find("to"))))
    if not entries:
        return None

    start = root.find("starttime")
    position = 0.0
    if start is not None:
        def part(name, fallback):
            try:
                return int(start.findtext(name, ""))
            except ValueError:
                return fallback
        try:
            origin = time.mktime((part("year", 2000), part("month", 1),
                                  part("day", 1), part("hour", 0),
                                  part("minute", 0), part("second", 0),
                                  0, 0, -1))
        except (OverflowError, ValueError):
            origin = 0.0
        total = sum(duration for duration, _file in entries)
        if total > 0:
            position = ((now if now is not None else time.time()) - origin) % total
    for duration, chosen in entries:
        if position < duration:
            return chosen
        position -= duration
    return entries[0][1]


# ---------- The suggestions ----------

# As the eye expects to find them when there is nothing to go on: in hue order,
# each far enough along not to be mistaken for the next.
FIXED_HUES = (20.0, 62.0, 150.0, 190.0, 232.0, 268.0, 305.0, 350.0)

# Tried in this order, keeping the first ones that stay distinct. Analogous first
# because it is the set that looks right over the picture it came from: the
# blur behind already holds those colours, so the mix stays clean. Opposites
# later, where they have to fight the blur to show (MUDDY_SHARE sorts out the
# ones that lose). The 90s are what is left when all of those landed on
# something already showing.
HARMONIES = (
    (0.0, "Same hue, deeper", -1.0),
    (-30.0, "Analogous", 0.0),
    (30.0, "Analogous", 0.0),
    (150.0, "Split-complementary", 0.0),
    (-150.0, "Split-complementary", 0.0),
    (120.0, "Triadic", 0.0),
    (-120.0, "Triadic", 0.0),
    (180.0, "Complementary", 0.0),
    (60.0, "Wider analogous", 0.0),
    (-60.0, "Wider analogous", 0.0),
    (90.0, "Tetradic", 0.0),
    (-90.0, "Tetradic", 0.0),
    (0.0, "Same hue, brighter", 1.0),
)

# The last row: neutrals exactly as written, so that black is the sheets as they
# ship, byte for byte, then a set of classic deep tints on one depth.
CLASSIC_NEUTRALS = (("#000000", "Black, as shipped"),
                    ("#101014", "Graphite"))
CLASSIC_HUES = ((262.0, "Midnight"), (205.0, "Deep teal"), (155.0, "Forest"),
                (70.0, "Bronze"), (22.0, "Oxblood"), (330.0, "Aubergine"))
ROW_LENGTH = 8


class Suggestion:
    """One swatch: what to ask for, what to call it, how it looks on the glass."""

    def __init__(self, colour, role, ground, alpha):
        self.colour = colour
        self.role = role
        self.ground = ground
        self.alpha = alpha


class _Row:
    """A row being filled, which refuses anything too like what it holds."""

    def __init__(self, model, backdrop, others=()):
        self._model = model
        self._backdrop = backdrop
        self._seen = list(others)
        self.suggestions = []
        # A share of what a surface's chroma is meant to be, so "too like" scales
        # with how much colour that surface shows at all.
        self._gap = GOALS[model.target][1] * 0.42

    @property
    def full(self):
        return len(self.suggestions) >= ROW_LENGTH

    @property
    def seen(self):
        return self._seen

    def _suggestion(self, tint, role):
        ground, alpha = self._model.ground(tint)
        return Suggestion(hex_of(tint), role, ground, alpha)

    def offer(self, hue, role, depth=0.0, vivid=1.0):
        if self.full:
            return False
        tint, lab, reached = fit_tint(hue, self._model, self._backdrop, depth, vivid)
        if reached < MUDDY_SHARE or any(
                _distance(lab, other) < self._gap for other in self._seen):
            return False
        self._seen.append(lab)
        self.suggestions.append(self._suggestion(tint, role))
        return True

    def pin(self, colour, role):
        tint = rgb_of(colour)
        self._seen.append(rgb_to_oklab(self._model.over(tint, self._backdrop.mean)))
        self.suggestions.append(self._suggestion(tint, role))


def _wallpaper_row(analysis, model):
    row = _Row(model, analysis.backdrop)
    for hue, vivid in analysis.hues[:ROW_LENGTH - 1]:
        row.offer(hue, "From your wallpaper", vivid=vivid)
    # With few colours in it, the wallpaper's own hues at other depths, rather
    # than something it doesn't contain. No further than 1.8: past that the
    # suggestion is near-black, and all near-blacks are one suggestion.
    for depth in (1.0, -1.0, 1.8, -1.8):
        for hue, vivid in analysis.hues[:3]:
            if len(row.suggestions) < ROW_LENGTH - 1:
                row.offer(hue, "From your wallpaper", depth=depth, vivid=vivid)
    if analysis.cast is not None:
        # The refined one: barely a colour, and the same barely-a-colour as the
        # picture behind it, which is why it never looks applied.
        row.offer(analysis.cast, "Your wallpaper's neutral", depth=-0.5, vivid=0.42)
    # Reading order: a run of hue is calmer on the eye than a ranking. Only the
    # order changes, not which colours made it.
    base = analysis.hues[0][0]
    row.suggestions.sort(key=lambda suggestion: (
        (_hue(rgb_to_oklab(rgb_of(suggestion.colour))) - base) % 360))
    return row


def _top_up(row, backdrop, model, above=()):
    """A row is never short: past what stays distinct, take what comes closest.

    A blur that greys everything offered, as a saturated wallpaper does on the
    shell, is one to give way to rather than leave a hole for. Never the same
    hex as a swatch already on screen, though, however similar it may look.
    """
    if row.full:
        return
    held = {suggestion.colour for suggestion in row.suggestions}
    held.update(suggestion.colour for suggestion in above)
    candidates = {}
    for depth in (0.6, -1.0, 1.4):
        for hue in FIXED_HUES:
            tint, lab, _reached = fit_tint(hue, model, backdrop, depth=depth)
            candidates[hex_of(tint)] = lab
    while not row.full:
        spare = [colour for colour in candidates if colour not in held]
        if not spare:
            # Every hue landing on a hex already showing is a surface that cannot
            # show colour at all, where one dark grey is as good as another.
            grey = next(colour for colour in (
                "#%02x%02x%02x" % (step, step, step) for step in range(256))
                if colour not in held)
            candidates[grey] = rgb_to_oklab(rgb_of(grey))
            spare = [grey]
        chosen = max(spare, key=lambda colour: min(
            (_distance(candidates[colour], lab) for lab in row.seen), default=1.0))
        held.add(chosen)
        row.pin(chosen, "Rich tint")


def _fixed_row(backdrop, model):
    row = _Row(model, backdrop)
    for hue in FIXED_HUES:
        row.offer(hue, "Rich tint", depth=0.6)
    _top_up(row, backdrop, model)
    return row


def _harmony_row(base, backdrop, model, first):
    row = _Row(model, backdrop, first.seen)
    for offset, role, depth in HARMONIES:
        row.offer((base + offset) % 360, role, depth=depth)
    # Everything distinct at this depth is taken: the same wheel, a step off it.
    for depth in (1.0, -1.0):
        for offset, role, _depth in HARMONIES:
            row.offer((base + offset) % 360, role, depth=depth)
    _top_up(row, backdrop, model, first.suggestions)
    return row


def _classic_row(accent_hue, accent_name, backdrop, model):
    row = _Row(model, backdrop)
    for colour, role in CLASSIC_NEUTRALS:
        row.pin(colour, role)
    if accent_hue is not None:
        row.offer(accent_hue, "Your %s accent" % accent_name)
    for hue, role in CLASSIC_HUES:
        # Next to the accent, one of these is just the accent again.
        if accent_hue is None or _hue_gap(hue, accent_hue) >= MIN_HUE_GAP:
            row.offer(hue, role)
    for hue, role in CLASSIC_HUES:
        row.offer(hue, role, depth=-1.0)
    _top_up(row, backdrop, model)
    return row


def suggest(analysis, model, accent=None, accent_name="desktop"):
    """Three rows of ROW_LENGTH suggestions, as [(title, [Suggestion, ...]), ...].

    The first two follow the wallpaper. A wallpaper that could not be read, or
    that has no colour to speak of, gives them the fixed set and the accent's
    harmonies, so the rows are the same size in every case.
    """
    accent_hue = None
    if accent is not None:
        lab = rgb_to_oklab(rgb_of(accent))
        if _chroma(lab) >= MIN_CHROMA:
            accent_hue = _hue(lab)

    backdrop = analysis.backdrop if analysis is not None else FALLBACK
    if analysis is not None and analysis.hues:
        first = _wallpaper_row(analysis, model)
        first_title = "From your wallpaper"
        base = analysis.hues[0][0]
        second_title = "In harmony with it"
    else:
        first = _fixed_row(backdrop, model)
        first_title = "Rich tints"
        # No slate to build a harmony on: the slate accent is a near-grey, and
        # blue is what its faint cast is.
        base = accent_hue if accent_hue is not None else 262.0
        second_title = "In harmony with your accent"

    # A picture too bare to fill its own row borrows from the fixed set.
    for hue in FIXED_HUES:
        first.offer(hue, "Rich tint", depth=0.6)
    _top_up(first, backdrop, model)

    second = _harmony_row(base, backdrop, model, first)
    third = _classic_row(accent_hue, accent_name, backdrop, model)
    return [(first_title, first.suggestions),
            (second_title, second.suggestions),
            ("Classics", third.suggestions)]
