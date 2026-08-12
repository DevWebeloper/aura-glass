# tahoe-glass design tokens — the single source of truth for every value that
# is written down in more than one place.
#
# This file is sourced, not templated. GTK4's var() fails at computed-value
# time rather than parse time (see the header of css/gtk4-transparency.css for
# the surface-blanking bug that caused), St has no custom properties at all,
# and GTK3's CSS engine predates them — so there is no cross-toolkit way to
# express a shared number as a variable. Generating the CSS from templates was
# the other option and was rejected: every non-obvious number in css/ carries a
# comment explaining why it is that number, and those comments are the most
# valuable thing in this repository.
#
# So the values still live literally in the files that use them, and this file
# plus tools/check-tokens.sh make the duplication *checked* instead of trusted.
# Change a value here, run tools/check-tokens.sh, and it names every file still
# disagreeing. That is the whole mechanism.
#
# Each token's comment lists every consumer. Keep those lists accurate — the
# checker's manifest is derived from the same pairings, and a token whose
# consumers are undocumented is a token that will drift again.

# ---------- Radii ----------
#
# The project rule, repeated in css/gtk3-tweaks.css and css/shell-tweaks.css:
# a painted radius must always equal the blur radius behind it. Blur My Shell
# rounds the blur actor; the CSS rounds the surface drawn on top of it. When
# they disagree the smaller shape leaves a sliver of the larger one showing,
# which reads as a rendering fault rather than as a wrong number.

# Window corners. The theme's libadwaita override already paints
# `window { border-radius: 30px }`; GTK3 windows and the blur behind every
# window have to agree with it.
#   css/gtk3-tweaks.css   decoration, .titlebar/.titlebar.background
#   dconf/core.ini        [blur-my-shell/applications] corner-radius
TOKEN_RADIUS_WINDOW=30

# Ordinary popup menus.
#   css/shell-tweaks.css  .popup-menu-content
#   dconf/core.ini        [blur-my-shell/popup] menu-corner-radius
TOKEN_RADIUS_MENU=26

# Quick Settings and the date menu. Blur My Shell groups these two with each
# other rather than with .popup-menu-content — its popup component matches on
# style class, and 'quick-settings', 'quick-toggle-menu' and 'datemenu-popover'
# share one key. That is why the date menu is not on TOKEN_RADIUS_MENU despite
# also being a .popup-menu-content, and it is not guessable from the selector.
#   css/shell-tweaks.css  .datemenu-popover, .popup-menu-content.quick-settings
#   dconf/core.ini        [blur-my-shell/popup] quick-settings-corner-radius
TOKEN_RADIUS_QUICK_SETTINGS=33

# Notifications, both in the calendar popup and as arriving banners.
#   css/shell-tweaks.css  .message, .notification-banner
#   dconf/core.ini        [blur-my-shell/popup] notification-corner-radius
TOKEN_RADIUS_NOTIFICATION=20

# Modal dialogs (log out, restart, power off).
#   css/shell-tweaks.css  .modal-dialog, .end-session-dialog
#   dconf/core.ini        [blur-my-shell/popup] dialog-corner-radius
TOKEN_RADIUS_DIALOG=20

# The generic popup fallback, for surfaces the more specific keys above do not
# claim. dconf only — nothing in css/ paints against it.
#   dconf/core.ini        [blur-my-shell/popup] corner-radius
TOKEN_RADIUS_POPUP=20

# The volume/brightness OSD. dconf only: Custom OSD draws the pill and Blur My
# Shell rounds the blur, so there is no CSS counterpart to keep in step.
#
# This key does NOT clamp, whatever the old comment in dconf/core.ini claimed.
# Past half the blurred box's height the four corner arcs overlap and the OSD
# turns into a soft ellipse — which is what 100 produced. The box being blurred
# is the stock .osd-window, far shorter than the pill Custom OSD draws inside
# it, so any value estimated from the *pill* comes out far too large. 12 was
# found by bisecting 0 (hard rectangle) against 25 (bulging). Raise it only
# against a screenshot.
#   dconf/core.ini        [blur-my-shell/popup] osd-corner-radius
TOKEN_RADIUS_OSD=12

# ---------- Blur My Shell sigmas ----------
#
# Every pipeline uses the native_static_gaussian_blur effect, whose cost scales
# with radius. Two things compound that:
#
#   1. hacks-level=2 (dconf/core.ini) turns off clipped redraws, which is the
#      fix for blur actors going stale when what is behind them moves. The cost
#      is a full-screen repaint every frame, for everything.
#   2. The panel is the only surface that is both always visible and always
#      blurred, so it is the only one paying that multiplier continuously
#      rather than for the few seconds a popup is open.
#
# Sigma changes here are design decisions with a measurable cost. Change one,
# measure it in the preview harness, and record the number — do not batch them.

# Measured, not assumed: dropping this to 20 and back over three preview runs
# moved the median not at all (22/22/22) and the p90 by less than the noise
# between two identical runs (28/29/31). The panel being always-on makes it the
# most expensive *pipeline*, but the cost that matters is Blur My Shell running
# at all — which is what --no-blur removes and what actually measures. Do not
# lower this expecting a GPU win; lower it only if you want a softer panel.
TOKEN_SIGMA_PANEL=30
TOKEN_SIGMA_APPFOLDER=50        # transient, but an outlier above every other
                                # pipeline's ~30 ceiling for no recorded reason.
TOKEN_SIGMA_POPUP=30
TOKEN_SIGMA_WINDOW_LIST=30
# Only ever applied when --app-transparency is on: the window blur is off in
# dconf/core.ini and install.sh turns it on to follow that flag. Leaving it on
# by default was the single most expensive thing in this preset — overview p90
# GPU busy 99% against 28% with it off, on an RX 7600 — and with the window at
# 94% opacity almost none of it reached the screen.
TOKEN_SIGMA_APPLICATIONS=12
TOKEN_SIGMA_DASH_TO_DOCK=4      # the cheap end of the range, kept as reference.

# ---------- App transparency ----------
#
# The level css/gtk4-transparency.css is *written* at. install_transparency_css
# in lib/steps.sh rescales every alpha in the installed copy relative to this
# baseline, so that the ladder between surfaces survives being retuned. It is
# therefore not merely a default — changing it without rewriting the sheet's
# own alphas changes what every other level means.
#
#   install.sh                    --app-transparency default and its help text
#   lib/steps.sh                  SHIPPED, in install_transparency_css
#   css/gtk4-transparency.css     the alpha() values themselves
TOKEN_APP_TRANSPARENCY_SHIPPED=0.92

# How much of the theme's own colour survives in a translucent app window, as a
# percentage; the rest is black. Darkening and thinning are opposite knobs —
# --app-transparency decides how much shows through, this decides how dark what
# remains is — and the second is what keeps text legible as the first goes up.
#
# It matters most with --no-blur, where what shows through is the wallpaper at
# full brightness rather than a blur. At 100 the window is the theme's colour
# and a bright wallpaper prints straight through it.
#
# Unlike the level above this is not rescaled per install — it is a design
# decision, written literally in both spellings in the sheet and checked against
# this token. Change it here, run tools/check-tokens.sh, and it names the lines
# that still disagree. The mix() weight is the complement (100 - this).
#
#   css/gtk4-transparency.css   the @define-color and :root tint blocks
TOKEN_APP_TINT=45

# ---------- Not tokens, deliberately ----------
#
# The accent colour is already live-plumbed through GNOME's own machinery: the
# shell CSS reads -st-accent-color and the GTK CSS reads @accent_bg_color, so
# Settings -> Appearance recolours the desktop without a file being touched.
# Pinning it here would be a downgrade. See the README's "Custom colours".
#
# Values that appear exactly once (the .quick-slider capsule at 26px, the
# gtk4 field radius at 10px, the tooltip at 12px) are not listed. A token for a
# value with one consumer cannot catch drift, and only adds a second place to
# forget to update.
