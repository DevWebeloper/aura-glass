/* aura-glass window-menu blur toggle, top-bar adaptive profile menu,
 * and session D-Bus bridge for settings and adaptive performance.
 *
 * The per-app blur allow/block list Blur My Shell reads is otherwise editable
 * in exactly two places: --app-blur-allow/--app-blur-block on install.sh, and
 * the Per-app blur page in the aura-glass settings window. This puts the same
 * question right where it gets asked — right-click the titlebar, "Blur This App" —
 * by monkeypatching WindowMenu._buildMenu.
 *
 * This extension also hosts Aura Glass's top-bar adaptive profile menu (Auto,
 * Full Glass, Performance) and exports the D-Bus bridge on
 * io.github.DevWebeloper.AuraGlass at /io/github/DevWebeloper/AuraGlass.
 * It answers ListWindows (for the settings app's "Open now" list), GetFocusState,
 * and emits WindowsChanged and FocusChanged signals.
 *
 * It also shades the top bar while a window on the active workspace fills
 * the panel's monitor (PANEL_SHADE_CLASS, painted by css/shell-00-flat.css),
 * in step with the motion that brought it (_syncPanelShade).
 *
 * And it lets the mouse wheel switch workspaces while a window or app icon
 * is held in the overview (_attachDragScroll), and takes a window dropped
 * near a workspace rather than only exactly on it (_hookDropTargets).
 *
 * And it sets how fast windows, notification banners and menus animate
 * (_syncEaseHook), from the three *-animation-speed memos.
 *
 * And it starts keyboard focus on Log Out in the log out dialog, where stock
 * GNOME starts it on Cancel (_hookEndSessionDialog).
 *
 * It stays installed and enabled in every mode, Performance included.
 */

import Clutter from 'gi://Clutter';
import Cogl from 'gi://Cogl';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {BoxPointer} from 'resource:///org/gnome/shell/ui/boxpointer.js';
import * as DND from 'resource:///org/gnome/shell/ui/dnd.js';
import {EndSessionDialog} from 'resource:///org/gnome/shell/ui/endSessionDialog.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {WindowMenu} from 'resource:///org/gnome/shell/ui/windowMenu.js';
import {ThumbnailsBox} from 'resource:///org/gnome/shell/ui/workspaceThumbnail.js';
import {TilePreview} from 'resource:///org/gnome/shell/ui/windowManager.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

const BMS_UUID = 'blur-my-shell@aunetx';
const BMS_SCHEMA_ID = 'org.gnome.shell.extensions.blur-my-shell.applications';
// DialogType.LOGOUT in endSessionDialog.js, which doesn't export the enum.
const END_SESSION_TYPE_LOGOUT = 0;

// Pinned back onto the whitelist by every install.sh run (app_blur_pin_allow
// in lib/steps-dconf.sh) — the same string is duplicated in
// gui/aura_glass_settings.py (SELF_WM_CLASS) and checked against this one by
// tools/check-app-blur-lists.sh.
const SELF_WM_CLASS = 'io.github.DevWebeloper.AuraGlassSettings';
// The top-bar indicator uses Aura Glass's own application icon rather than
// cycling through profile status glyphs, keeping a recognizable identity in the panel.
// Its symbolic version (gui/icons, installed by install_gui): the full-colour
// tile through the white-glyph effect below is one solid white square, since
// none of it is near-white. The symbolic ring is white already, so the effect
// leaves it alone.
const APP_ICON = `${SELF_WM_CLASS}-symbolic`;
// apply_top_bar_icon in lib/steps-dconf.sh writes this: '0' hides the indicator,
// and anything else, a missing file included, shows it.
const TOP_BAR_ICON_FILE = 'top-bar-icon';

// How far into a thumbnail, from each side, a held window means "a new workspace
// here" rather than "this workspace". GNOME's 10px gave a quarter of an 81px
// thumbnail (1920x1080) to new workspaces, so a window aimed at workspace 1 and
// let go near the thumbnail's edge made a workspace instead. At 4px the zone
// between two thumbnails is still 12px wide with the theme's 4px spacing.
const THUMBNAIL_NEW_WORKSPACE_PX = 4;
// How far outside the 44px thumbnail row a dropped window still counts as dropped
// on the thumbnail nearest it. GNOME cancels a drop there. 20px is under half a
// thumbnail's height: it forgives a miss and stays this side of the top bar, which
// is above the overview's controls and so never asks.
const THUMBNAIL_DROP_SLACK_PX = 20;

// The top bar is drawn in one colour: white glyphs, the way the system icons
// already are. Tray icons from apps are not. Discord and Claude hand over a
// coloured PNG, Telegram asks for a symbolic name the icon pack does not have
// and falls back to its coloured pixmap, and this helper's own indicator is the
// coloured application icon. So each of those is drawn through this effect: any
// pixel with colour or darkness in it becomes white, and a near-white pixel
// becomes a hole. That turns a logo's white details (Telegram's plane,
// Discord's eyes) into cut-outs instead of losing them in a white blob. The
// thresholds are where a white detail with anti-aliased edges reads cleanly at
// 16px: below 0.75 on the darkest channel is ink, above 0.92 is a hole. Icons
// that are already symbolic are left alone, since they are white already and
// this would cut them out entirely.
const WHITE_GLYPH_GLSL = `
    if (cogl_color_out.a > 0.0) {
        vec3 rgb = cogl_color_out.rgb / cogl_color_out.a;
        float lowest = min(min(rgb.r, rgb.g), rgb.b);
        float ink = cogl_color_out.a * (1.0 - smoothstep(0.75, 0.92, lowest));
        cogl_color_out = vec4(ink, ink, ink, ink);
    }
`;

// A Clutter.ShaderEffect with a static snippet, the way GNOME's own lightbox
// builds its vignette: Shell.GLSLEffect is not in every Shell this supports.
// The snippet's code runs after the icon's texture has been sampled into
// cogl_color_out, which is premultiplied.
const WhiteGlyphEffect = GObject.registerClass(
class AuraGlassWhiteGlyphEffect extends Clutter.ShaderEffect {
    vfunc_get_static_snippet() {
        return Cogl.Snippet.new(Cogl.SnippetHook.FRAGMENT, '', WHITE_GLYPH_GLSL);
    }
});

const WHITE_GLYPH_EFFECT = 'aura-glass-white-glyph';

// Written by bin/aura-glass-update when it reopens the settings window after
// an install: the pid of the update window that was in front. The reopened
// settings window would otherwise take the focus from it while the update
// window still has its Log out / Later question up. A client cannot hand the
// focus back on Wayland, but the shell can, so the helper does it.
const KEEP_FOCUS_FILE = 'aura-glass-keep-focus';

const DBUS_NAME = 'io.github.DevWebeloper.AuraGlass';
const DBUS_PATH = '/io/github/DevWebeloper/AuraGlass';
const DBUS_IFACE = `
<node>
  <interface name="${DBUS_NAME}">
    <method name="ListWindows">
      <arg type="a(ssu)" direction="out" name="windows"/>
    </method>
    <signal name="WindowsChanged"/>
    <method name="GetFocusState">
      <arg type="b" direction="out" name="fullscreen"/>
      <arg type="s" direction="out" name="wm_class"/>
    </method>
    <method name="GetFullscreen">
      <arg type="b" direction="out" name="fullscreen"/>
    </method>
    <method name="SetWindowOpacity">
      <arg type="u" direction="in" name="opacity"/>
    </method>
    <method name="RefreshOpacity"/>
    <method name="ReloadTheme"/>
    <method name="InspectOverviewState">
      <arg type="s" direction="out" name="state"/>
    </method>
    <signal name="FocusChanged">
      <arg type="b" name="fullscreen"/>
      <arg type="s" name="wm_class"/>
    </signal>
  </interface>
</node>`;

// Added to Main.panel while the focused window fills the panel's monitor.
// css/shell-00-flat.css paints it; the name is duplicated there.
const PANEL_SHADE_CLASS = 'aura-glass-maximized';
// The shell's own durations for the two motions the shade rides on:
// WINDOW_ANIMATION_TIME in windowManager.js (a maximize or unmaximize, scaled
// by --window-animation-speed like the window itself) and ANIMATION_TIME in
// overview.js (the overview opening and closing, which is never scaled).
// The stylesheet's 250ms is the fallback while this extension is off.
const SHADE_WINDOW_MS = 250;
const SHADE_OVERVIEW_MS = 250;

// How long the fullscreen cover stays fully opaque after the window's new
// size, before it fades to the live window (_coverFullscreenChange). A
// screencast of YouTube in Chrome put the page's re-layout 175-210 ms after
// the new size, on every toggle in and out. Set just under the earliest, so
// the still is held no longer than the page needs. The page's time, not an
// animation's, so the animation speeds leave it alone.
const FULLSCREEN_SETTLE_MS = 170;

// The longest the fullscreen cover waits over the window for the client's
// new size (_holdFullscreenCover). The wait measured 100-313 ms from a
// screencast of YouTube in Chrome; past this the client is taken not to
// answer, the cover goes, and GNOME's still is used if the size comes later.
const FULLSCREEN_WAIT_MS = 1000;

const PROFILES = ['auto', 'full', 'performance'];
// State files whose change can move the window opacity this extension owns.
const OPACITY_STATE_FILES = new Set([
    'app-opacity', 'app-transparency', 'glass-mode', 'adaptive-performance', 'active',
]);
// Written by bin/aura-glass-apply: shell rules for surfaces another extension
// paints from its own stylesheet (Copyous's Super+V dialog). St ranks every
// extension-loaded sheet above the shell theme, so these only win when they
// are loaded as one too, which is what this extension does with it.
const OVERRIDE_SHEET = 'extension-overrides.css';
// --window-, --notification- and --menu-animation-speed, written by
// apply_animation_speed in lib/steps-dconf.sh: a percentage of GNOME's own
// pace, so 200 halves every duration and 50 doubles it. The bounds and the
// shipped 100 are duplicated there (ANIMATION_SPEED_*) and in
// gui/aura_glass_settings.py; a memo outside them reads as 100, as the
// installer resolves it.
const ANIMATION_SPEED_FILES = {
    window: 'window-animation-speed',
    notification: 'notification-animation-speed',
    menu: 'menu-animation-speed',
};
const ANIMATION_SPEED_STATE_FILES = new Set(Object.values(ANIMATION_SPEED_FILES));
const ANIMATION_SPEED_MIN = 50;
const ANIMATION_SPEED_MAX = 300;
const ANIMATION_SPEED_SHIPPED = 100;
const PROFILE_ICONS = {
    auto: 'view-refresh-symbolic',
    full: 'weather-clear-symbolic',
    performance: 'system-run-symbolic',
};

function configPath(...parts) {
    return GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass', ...parts]);
}

function readState(...parts) {
    try {
        const [ok, bytes] = GLib.file_get_contents(configPath(...parts));
        return ok ? new TextDecoder().decode(bytes).trim() : '';
    } catch (error) {
        return '';
    }
}

// Mirrors Blur My Shell's own components/applications/window_rules.js wildcard_to_regex:
// escape every regex metacharacter except * and ?, anchor at both ends,
// * -> .*, ? -> ., case-insensitive. Brackets are escaped rather than left to
// form a character class, so [abc] matches the three literal characters —
// this has to agree with that function exactly, or this toggle and the
// allow/block list in the settings window would disagree about what a
// pattern covers. lib/steps-dconf.sh (app_blur_covers_self) and
// gui/aura_glass_settings.py (pattern_matches) are the other two mirrors.
function wildcardToRegex(pattern) {
    const escaped = pattern
        .replace(/[.+^${}()|[\]\\]/g, '\\$&')
        .replace(/\*/g, '.*')
        .replace(/\?/g, '.');
    return new RegExp(`^${escaped}$`, 'i');
}

// A title: entry (upstream #1217) tests the window titles and any other entry
// the classes, as to_rule does in Blur My Shell's window_rules.js.
const TITLE_PREFIX = 'title:';

function matchesAny(patterns, values) {
    return patterns.some(p => p.trim() !== '' &&
        values.some(v => wildcardToRegex(p).test(v)));
}

function matchesAnyRule(patterns, {classes, titles}) {
    const isTitle = p => p.trim().startsWith(TITLE_PREFIX);
    return matchesAny(patterns.filter(p => !isTitle(p)), classes) ||
        matchesAny(patterns.filter(isTitle).map(p => p.trim().slice(TITLE_PREFIX.length)), titles);
}

// Mirrors patches/blur-my-shell-subwindows.patch's window_chain: a window, then
// each window up its transient-for chain — so right-clicking a dialog's
// titlebar toggles the app it belongs to, and the checkbox reads as checked
// when that app is blurred, not only when the dialog's own (often different,
// sometimes empty) class happens to be on the list. Bounded and cycle-guarded
// for the same reason the patch's copy is: transient-for loops are malformed
// but a client can still set one.
function windowChain(window) {
    const chain = [window];
    const seen = new Set(chain);
    let parent = window.get_transient_for();
    for (let depth = 0; parent && depth < 8 && !seen.has(parent); depth++) {
        seen.add(parent);
        chain.push(parent);
        parent = parent.get_transient_for();
    }
    return chain;
}

// Every wm_class and GTK application id on that chain, nearest first.
function windowClasses(window) {
    const classes = [];
    const push = v => { if (v && !classes.includes(v)) classes.push(v); };
    for (const member of windowChain(window)) {
        push(member.get_wm_class());
        push(member.get_gtk_application_id());
    }
    return classes;
}

// What the rules are asked about, taken while the window is known to exist: the
// menu's toggle reads it again when the backend answers, usually after the menu
// and possibly the window have gone.
function windowIdentity(window) {
    return {
        classes: windowClasses(window),
        titles: windowChain(window).map(member => member.get_title()).filter(Boolean),
    };
}

// The root class a window belongs to, for both the window-menu toggle and the
// D-Bus bridge: the last entry in the transient-for chain, so a dialog
// resolves to the app it belongs to rather than to its own (often different,
// sometimes absent) class.
function rootWindowClass(window) {
    const classes = windowClasses(window);
    return classes.length ? classes[classes.length - 1] : null;
}

// A window that fills the screen, for the top-bar shade: maximized both ways,
// fullscreen, or sized over the whole work area without either flag. (The same
// test chooses static blur behind such a window: covers_monitor in
// patches/blur-my-shell-static-maximized.patch.) The last is Tiling Assistant's
// drag-to-top or maximize with maximize-with-gap on: it resizes to the work area
// instead of maximizing, so GTK never sees the window as maximized either.
function coversMonitor(window) {
    if (window.fullscreen ||
        (window.maximized_horizontally && window.maximized_vertically))
        return true;
    const area = window.get_work_area_current_monitor();
    const frame = window.get_frame_rect();
    return frame.x <= area.x && frame.y <= area.y &&
        frame.x + frame.width >= area.x + area.width &&
        frame.y + frame.height >= area.y + area.height;
}

// The same frame-type gate Blur My Shell's components/applications/window_rules.js
// applies (patched by patches/blur-my-shell-subwindows.patch to include
// ATTACHED and UTILITY too) — a window neither this nor Blur My
// Shell would ever blur is not offered up as something to blur.
function isBlurrable(frameType) {
    return frameType === Meta.FrameType.NORMAL ||
        frameType === Meta.FrameType.DIALOG ||
        frameType === Meta.FrameType.MODAL_DIALOG ||
        frameType === Meta.FrameType.ATTACHED ||
        frameType === Meta.FrameType.UTILITY;
}

export default class AuraGlassBlurExtension extends Extension {
    enable() {
        this._profileLabels = {
            auto: _('Auto'),
            full: _('Frost Glass'),
            performance: _('Performance'),
        };
        this._fullscreen = false;
        this._focusedWmClass = '';
        this._focusedWindow = null;
        this._focusedWindowFullscreenId = 0;
        this._focusedWindowGeometryIds = [];

        this._settings = this._openBmsApplicationsSettings();
        this._syncWindowMenu();
        this._hookEndSessionDialog();

        this._extStateChangedId = Main.extensionManager?.connect?.(
            'extension-state-changed', (_mgr, ext) => {
                if (ext.uuid === BMS_UUID) {
                    if (ext.state === 1) {
                        this._settings = this._openBmsApplicationsSettings();
                        this._syncWindowMenu();
                    } else {
                        this._settings = null;
                    }
                    this._updateOpacityFromConfig();
                }
            }) ?? 0;

        this._dbusImpl = Gio.DBusExportedObject.wrapJSObject(DBUS_IFACE, this);
        this._dbusImpl.export(Gio.DBus.session, DBUS_PATH);
        this._nameOwnerId = Gio.bus_own_name(
            Gio.BusType.SESSION, DBUS_NAME, Gio.BusNameOwnerFlags.NONE,
            null, null, null);

        this._windowsChangedTimer = 0;
        this._windowCreatedId = global.display.connect('window-created',
            (_display, window) => this._trackWindow(window));
        this._destroyIds = new Map();
        for (const actor of global.get_window_actors())
            this._trackWindow(actor.get_meta_window());

        this._shadeActive = true;
        this._shadeKey = null;

        // The overview gives the top bar its own look, so the shade lifts
        // while it is open. Both edges follow the overview's own animation,
        // as GNOME's panel does with its :overview style: lifted on showing,
        // back on hiding, so it fades in with the windows coming back. It
        // used to come back on hidden, after the windows had landed, and the
        // bar went clear and then dark again: a flash.
        this._overviewShown = Main.overview.visible;
        this._overviewIds = [
            Main.overview.connect('showing', () => {
                this._overviewShown = true;
                this._syncPanelShade(SHADE_OVERVIEW_MS);
            }),
            Main.overview.connect('hiding', () => {
                this._overviewShown = false;
                this._syncPanelShade(SHADE_OVERVIEW_MS);
            }),
        ];
        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => {
                this._syncPanelShade();
                this._queueDisplaySync();
            });
        // Also now: a layout changed while the session was locked or logged out
        // sent its signal to nobody.
        this._queueDisplaySync();
        // A maximized window behind a smaller focused one (the settings app
        // over Chrome) still fills the screen, so the shade follows every
        // window on the workspace, not only the focused one: restacked
        // covers a raise, a minimize, an unminimize and a close, and a
        // workspace switch brings a different set.
        this._shadeStackIds = [
            global.display.connect('restacked', () => this._syncPanelShade()),
            global.workspace_manager.connect('active-workspace-changed',
                () => this._syncPanelShade()),
        ];

        this._focusWindowId = global.display.connect(
            'focus-window', (_display, window) => this._watchFocusedWindow(window));
        this._watchFocusedWindow(global.display.focusWindow ?? global.display.focus_window);

        // GNOME's DnD pushes a modal grab onto a private 0x0 actor for the
        // whole drag, so scroll never reaches the overview's workspace
        // switcher. The grab is taken before 'drag-begin' fires, so these
        // signals can read it off the stage.
        this._dragScrollActor = null;
        this._dragScrollId = 0;
        const dragBegin = () => {
            this._attachDragScroll();
            this._delegateOtherScreens();
        };
        const dragEnd = () => this._detachDragScroll();
        this._dragIds = [
            Main.overview.connect('window-drag-begin', dragBegin),
            Main.overview.connect('item-drag-begin', dragBegin),
            Main.overview.connect('window-drag-end', dragEnd),
            Main.overview.connect('window-drag-cancelled', dragEnd),
            Main.overview.connect('item-drag-end', dragEnd),
            Main.overview.connect('item-drag-cancelled', dragEnd),
        ];

        this._hookDropTargets();
        this._buildPanelMenu();
        this._hookWhiteIcons();
        this._initOpacityMonitor();
        this._loadOverrideSheet();
        this._readAnimationSpeeds();
        this._hookFullscreenTransition();
    }

    _attachDragScroll() {
        this._detachDragScroll();
        const actor = global.stage.get_grab_actor();
        if (!actor)
            return;
        this._dragScrollActor = actor;
        this._dragScrollId = actor.connect('scroll-event',
            (_actor, event) => this._onDragScroll(event));
    }

    _detachDragScroll() {
        if (this._dragScrollActor && this._dragScrollId)
            this._dragScrollActor.disconnect(this._dragScrollId);
        this._dragScrollActor = null;
        this._dragScrollId = 0;
    }

    // Mouse wheel only: handleWorkspaceScroll passes smooth (touchpad) scroll
    // through, so a touchpad scroll still reaches the drag as before.
    _onDragScroll(event) {
        if (!Main.overview.visible)
            return Clutter.EVENT_PROPAGATE;
        return Main.wm.handleWorkspaceScroll(event);
    }

    // A window dragged to another workspace only landed if it was let go inside a
    // strip of the thumbnail or on the neighbour's own edge of the screen. Near
    // misses cancelled it or made a new workspace, so the same gesture worked only
    // sometimes. Apart from the cut size, a drop that had a target keeps it: DND's
    // walk up from the picked actor reaches these delegates only once every target
    // below them has refused, and the actors they sit on had none of their own.
    _hookDropTargets() {
        const proto = ThumbnailsBox.prototype;
        this._origPlaceholderTarget = proto._getPlaceholderTarget;
        this._origWithinWorkspace = proto._withinWorkspace;

        // GNOME's two methods with their cut size replaced, which is a constant
        // private to its module.
        proto._getPlaceholderTarget = function (index, spacing, rtl) {
            const workspace = this._thumbnails[index];
            let targetX1, targetX2;
            if (rtl) {
                const baseX = workspace.x + workspace.width;
                targetX1 = baseX - THUMBNAIL_NEW_WORKSPACE_PX;
                targetX2 = baseX + spacing + THUMBNAIL_NEW_WORKSPACE_PX;
            } else {
                targetX1 = workspace.x - spacing - THUMBNAIL_NEW_WORKSPACE_PX;
                targetX2 = workspace.x + THUMBNAIL_NEW_WORKSPACE_PX;
            }
            if (index === 0) {
                if (rtl)
                    targetX2 -= spacing + THUMBNAIL_NEW_WORKSPACE_PX;
                else
                    targetX1 += spacing + THUMBNAIL_NEW_WORKSPACE_PX;
            }
            if (index === this._dropPlaceholderPos) {
                const placeholderWidth = this._dropPlaceholder.get_width() + spacing;
                if (rtl)
                    targetX2 += placeholderWidth;
                else
                    targetX1 -= placeholderWidth;
            }
            return [targetX1, targetX2];
        };
        proto._withinWorkspace = function (x, index, rtl) {
            const workspace = this._thumbnails[index];
            let x1 = workspace.x + THUMBNAIL_NEW_WORKSPACE_PX;
            let x2 = workspace.x + workspace.width - THUMBNAIL_NEW_WORKSPACE_PX;
            if (index === this._thumbnails.length - 1) {
                if (rtl)
                    x1 -= THUMBNAIL_NEW_WORKSPACE_PX;
                else
                    x2 += THUMBNAIL_NEW_WORKSPACE_PX;
            }
            return x > x1 && x <= x2;
        };

        // Windows only: an app icon let go here keeps GNOME's answer.
        const controls = Main.overview._overview?.controls;
        if (!controls)
            return;
        const targetFor = (source, x, y) => {
            if (!source.metaWindow)
                return null;
            const [originX, originY] = controls.get_transformed_position();
            return this._workspaceNear(controls, originX + x, originY + y);
        };
        controls._delegate = {
            handleDragOver: (source, actor, x, y, time) =>
                targetFor(source, x, y)?.handleDragOver(source, actor, x, y, time) ??
                    DND.DragMotionResult.CONTINUE,
            acceptDrop: (source, actor, x, y, time) =>
                targetFor(source, x, y)?.acceptDrop(source, actor, x, y, time) ?? false,
        };
        this._dropControls = controls;
    }

    _unhookDropTargets() {
        const proto = ThumbnailsBox.prototype;
        if (this._origPlaceholderTarget)
            proto._getPlaceholderTarget = this._origPlaceholderTarget;
        if (this._origWithinWorkspace)
            proto._withinWorkspace = this._origWithinWorkspace;
        this._origPlaceholderTarget = null;
        this._origWithinWorkspace = null;
        this._dropControls?._workspacesDisplay._workspacesViews.forEach(view => {
            if (view._workspacesView)
                delete view._delegate;
        });
        if (this._dropControls)
            delete this._dropControls._delegate;
        this._dropControls = null;
    }

    // Another screen's workspace leaves a margin above and below it, where a window
    // let go on that screen was cancelled. The views are rebuilt each time the overview
    // opens, so they are reached when a drag starts. Only those views have a
    // _workspacesView.
    _delegateOtherScreens() {
        this._dropControls?._workspacesDisplay._workspacesViews.forEach(view => {
            if (!view._workspacesView || view._delegate)
                return;
            const target = source => (source.metaWindow
                ? view._workspacesView.getActiveWorkspace()
                : null);
            view._delegate = {
                handleDragOver: (source, actor, x, y, time) =>
                    target(source)?.handleDragOver(source, actor, x, y, time) ??
                        DND.DragMotionResult.CONTINUE,
                acceptDrop: (source, actor, x, y, time) =>
                    target(source)?.acceptDrop(source, actor, x, y, time) ?? false,
            };
        });
    }

    // The primary monitor's workspace a stage point is a near miss of: the thumbnail
    // nearest it within the slack, or the neighbour on that side when it is in the
    // gap between the active workspace and the neighbour's edge of the screen.
    _workspaceNear(controls, x, y) {
        const view = controls._workspacesDisplay._getPrimaryView();
        const workspaces = view?._workspaces;
        if (!workspaces)
            return null;

        const box = controls._thumbnailsBox;
        if (box.visible) {
            const [, boxY] = box.get_transformed_position();
            const [, boxHeight] = box.get_transformed_size();
            if (y >= boxY - THUMBNAIL_DROP_SLACK_PX &&
                y <= boxY + boxHeight + THUMBNAIL_DROP_SLACK_PX) {
                let nearest = null;
                let nearestDistance = THUMBNAIL_DROP_SLACK_PX;
                for (const thumbnail of box._thumbnails) {
                    const [thumbnailX] = thumbnail.get_transformed_position();
                    const [thumbnailWidth] = thumbnail.get_transformed_size();
                    const distance = Math.max(thumbnailX - x, x - thumbnailX - thumbnailWidth, 0);
                    if (distance <= nearestDistance) {
                        nearest = thumbnail;
                        nearestDistance = distance;
                    }
                }
                if (nearest)
                    return workspaces[nearest.metaWorkspace.index()] ?? null;
            }
        }

        const active = view.getActiveWorkspace();
        const [activeX, activeY] = active.get_transformed_position();
        const [activeWidth, activeHeight] = active.get_transformed_size();
        if (y < activeY || y > activeY + activeHeight ||
            (x >= activeX && x <= activeX + activeWidth))
            return null;
        const index = workspaces.indexOf(active);
        return [workspaces[index - 1], workspaces[index + 1]].find(workspace => {
            if (!workspace)
                return false;
            const [workspaceX] = workspace.get_transformed_position();
            return x < activeX ? workspaceX < activeX : workspaceX > activeX;
        }) ?? null;
    }

    // Main.loadTheme() carries extension sheets over to each new theme and
    // re-reads them, so the shell-theme reload after an apply picks up the new
    // file too. This covers a rewrite without one, and the first load.
    _loadOverrideSheet() {
        this._unloadOverrideSheet();
        const file = Gio.File.new_for_path(configPath(OVERRIDE_SHEET));
        if (!file.query_exists(null))
            return;
        try {
            St.ThemeContext.get_for_stage(global.stage).get_theme().load_stylesheet(file);
            this._overrideSheet = file;
        } catch (e) {
            // A sheet St cannot parse leaves Copyous on its own look
        }
    }

    _unloadOverrideSheet() {
        if (!this._overrideSheet)
            return;
        St.ThemeContext.get_for_stage(global.stage).get_theme().unload_stylesheet(this._overrideSheet);
        this._overrideSheet = null;
    }

    // --no-window-menu writes window-menu=0, and the conf monitor brings any
    // change here, so the item comes and goes without a reload.
    _syncWindowMenu() {
        if (this._settings && readState('window-menu') !== '0')
            this._hookWindowMenu();
        else
            this._unhookWindowMenu();
    }

    _unhookWindowMenu() {
        if (!this._origBuildMenu)
            return;
        WindowMenu.prototype._buildMenu = this._origBuildMenu;
        this._origBuildMenu = null;
    }

    _hookWindowMenu() {
        if (this._origBuildMenu)
            return;
        this._origBuildMenu = WindowMenu.prototype._buildMenu;
        const self = this;
        WindowMenu.prototype._buildMenu = function (window) {
            self._origBuildMenu.call(this, window);
            self._appendBlurToggle(this, window);
        };
    }

    // Log out only: power off and restart keep stock's focus on Cancel, since
    // a stray Enter there costs more. _updateButtons rebuilds the buttons on
    // every open, and a destroyed button clears the focus set here, so the
    // other dialog types sharing this instance don't inherit it.
    _hookEndSessionDialog() {
        this._origUpdateButtons = EndSessionDialog.prototype._updateButtons;
        const self = this;
        EndSessionDialog.prototype._updateButtons = function () {
            self._origUpdateButtons.call(this);
            if (this._type === END_SESSION_TYPE_LOGOUT)
                this.setInitialKeyFocus(this.dialogLayout.buttonLayout.get_last_child());
        };
    }

    _unhookEndSessionDialog() {
        EndSessionDialog.prototype._updateButtons = this._origUpdateButtons;
        this._origUpdateButtons = null;
    }

    _isBmsApplicationsActive() {
        const bmsEnabled = Boolean(global.blur_my_shell) ||
            Main.extensionManager?.lookup?.(BMS_UUID)?.state === 1;
        if (!bmsEnabled)
            return false;
        if (!this._settings)
            this._settings = this._openBmsApplicationsSettings();
        if (!this._settings)
            return false;
        try {
            return Boolean(this._settings.get_boolean('blur'));
        } catch (e) {
            return false;
        }
    }

    // Top bar icon size and pixel snapping are measured from the primary display.
    // Plugging in a monitor can fire this several times while mutter settles, so
    // it waits for two quiet seconds. Only the installed command is run: a nested
    // preview shell has a fixture $HOME without it, and must not retune the desktop.
    _queueDisplaySync() {
        if (this._displaySyncTimer)
            GLib.source_remove(this._displaySyncTimer);
        this._displaySyncTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this._displaySyncTimer = 0;
            const command = GLib.build_filenamev([
                GLib.get_home_dir(), '.local', 'bin', 'aura-glass-display-sync']);
            if (GLib.file_test(command, GLib.FileTest.IS_EXECUTABLE)) {
                try {
                    Gio.Subprocess.new([command],
                        Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
                } catch (error) {
                    console.warn(`aura-glass: display sync: ${error.message}`);
                }
            }
            return GLib.SOURCE_REMOVE;
        });
    }

    disable() {
        if (this._extStateChangedId) {
            Main.extensionManager?.disconnect?.(this._extStateChangedId);
            this._extStateChangedId = 0;
        }

        for (const [monitor, id] of this._confMonitors ?? []) {
            monitor.disconnect(id);
            monitor.cancel();
        }
        this._confMonitors = null;
        this._unloadOverrideSheet();
        this._unhookFullscreenTransition();
        this._unhookEase();

        if (!this._isBmsApplicationsActive()) {
            this.setWindowOpacityAll(255);
        }

        this._unhookWindowMenu();
        this._unhookEndSessionDialog();
        this._settings = null;

        if (this._focusWindowId) {
            global.display.disconnect(this._focusWindowId);
            this._focusWindowId = 0;
        }
        this._watchFocusedWindow(null);

        for (const id of this._overviewIds ?? [])
            Main.overview.disconnect(id);
        this._overviewIds = null;
        for (const id of this._dragIds ?? [])
            Main.overview.disconnect(id);
        this._dragIds = null;
        this._detachDragScroll();
        this._unhookDropTargets();
        if (this._displaySyncTimer) {
            GLib.source_remove(this._displaySyncTimer);
            this._displaySyncTimer = 0;
        }
        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = 0;
        }
        const [restackedId, workspaceId] = this._shadeStackIds ?? [];
        if (restackedId)
            global.display.disconnect(restackedId);
        if (workspaceId)
            global.workspace_manager.disconnect(workspaceId);
        this._shadeStackIds = null;
        this._shadeActive = false;
        Main.panel.set_style(null);
        Main.panel.remove_style_class_name(PANEL_SHADE_CLASS);

        if (this._windowsChangedTimer) {
            GLib.source_remove(this._windowsChangedTimer);
            this._windowsChangedTimer = 0;
        }
        if (this._windowCreatedId) {
            global.display.disconnect(this._windowCreatedId);
            this._windowCreatedId = 0;
        }
        if (this._destroyIds) {
            for (const [window, id] of this._destroyIds)
                window.disconnect(id);
            this._destroyIds = null;
        }

        this._unhookWhiteIcons();
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
        this._icon = null;
        this._statusItem = null;
        this._profileItems = null;
        this._profileLabels = null;

        if (this._nameOwnerId) {
            Gio.bus_unown_name(this._nameOwnerId);
            this._nameOwnerId = 0;
        }
        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
        }
    }

    _watchFocusedWindow(window) {
        if (this._focusedWindow && this._focusedWindowFullscreenId) {
            this._focusedWindow.disconnect(this._focusedWindowFullscreenId);
            this._focusedWindowFullscreenId = 0;
        }
        for (const id of this._focusedWindowGeometryIds)
            this._focusedWindow.disconnect(id);
        this._focusedWindowGeometryIds = [];
        this._focusedWindow = window ?? null;
        if (this._focusedWindow) {
            this._focusedWindowFullscreenId = this._focusedWindow.connect(
                'notify::fullscreen', () => {
                    this._updateFocusState();
                    // Entering fullscreen is not a maximize animation: Shell hides its own chrome
                    // on its own timeline while the video rescales itself, so the shade fading at
                    // maximize pace lands visibly off-beat. The panel sits hidden under a
                    // fullscreen window anyway, so it changes at once. Leaving clears the flag
                    // while the window is still the size of the monitor, so nothing changes here:
                    // the shade follows the shrink at size-changed, at maximize pace, as an
                    // unmaximize does.
                    this._syncPanelShade(0);
                });
            // size-changed and position-changed catch a tiler's resize to the
            // work area and a move to another monitor, which set no flag.
            this._focusedWindowGeometryIds = [
                'notify::maximized-horizontally',
                'notify::maximized-vertically',
                'size-changed',
                'position-changed',
            ].map(signal => this._focusedWindow.connect(signal,
                () => this._syncPanelShade()));
        }
        this._updateFocusState();
        this._syncPanelShade();
    }

    // The panel lives on the primary monitor, so a window filling another
    // monitor leaves it alone.
    //
    // The shade is the stylesheet's alone: black at the alpha the brightness
    // slider writes, the same over every app. It once took the covering
    // window's titlebar colour, read off the screen 300ms after the window
    // settled, but what showed through the translucent titlebar differed
    // with when it was read (unmaximized, mid-maximize, the overview's close
    // with the window's blur not back yet), so the bar came out a different
    // colour after a maximize than after leaving the overview.
    //
    // The fade takes the duration of the motion that caused it, inline so it
    // out-ranks the stylesheet's !important 250ms. Restyled only when the
    // look changes: St cancels a running fade on any new style, and the
    // restacks and geometry signals that come mid-motion would cut it short.
    _syncPanelShade(duration = this._shadeWindowDuration()) {
        if (!this._shadeActive)
            return;
        const primary = Main.layoutManager.primaryIndex;
        const workspace = global.workspace_manager.get_active_workspace();
        const covering = this._overviewShown ? [] : workspace.list_windows()
            .filter(window => !window.minimized && !window.skip_taskbar &&
                window.get_monitor() === primary && coversMonitor(window));
        const top = global.display.sort_windows_by_stacking(covering).at(-1);
        const key = top ? 'shade' : 'clear';
        if (key === this._shadeKey)
            return;
        this._shadeKey = key;
        Main.panel.set_style(`transition-duration: ${duration}ms;`);
        if (top)
            Main.panel.add_style_class_name(PANEL_SHADE_CLASS);
        else
            Main.panel.remove_style_class_name(PANEL_SHADE_CLASS);
    }

    _shadeWindowDuration() {
        return Math.round(SHADE_WINDOW_MS * (this._animationScale?.window ?? 1));
    }

    _updateFocusState() {
        const isFullscreen = Boolean(this._focusedWindow?.fullscreen);
        const wmClass = this._focusedWindow ? (rootWindowClass(this._focusedWindow) || this._focusedWindow.get_wm_class() || '') : '';
        if (isFullscreen === this._fullscreen && wmClass === this._focusedWmClass)
            return;
        this._fullscreen = isFullscreen;
        this._focusedWmClass = wmClass;
        if (this._dbusImpl) {
            this._dbusImpl.emit_signal('FocusChanged',
                new GLib.Variant('(bs)', [isFullscreen, wmClass]));
        }
    }

    // ---- White top bar icons ----------------------------------------------

    // The helper's own icon, and every AppIndicator icon: those that are in
    // the panel now, and those an app adds later (each lands in one of the
    // panel's three boxes). An icon is re-judged whenever it changes, because
    // an app can swap a symbolic icon for a coloured one (Telegram's unread
    // badge) or back.
    _hookWhiteIcons() {
        this._whiteIcons = new Map();
        this._watchWhiteIcon(this._icon);
        this._scanTrayIcons();
        this._panelBoxIds = [Main.panel._leftBox, Main.panel._centerBox,
            Main.panel._rightBox].map(box => [box,
            box.connect('child-added', () => this._scanTrayIcons())]);
    }

    _unhookWhiteIcons() {
        for (const [box, id] of this._panelBoxIds ?? [])
            box.disconnect(id);
        this._panelBoxIds = null;
        for (const [icon, ids] of this._whiteIcons ?? []) {
            for (const id of ids)
                icon.disconnect(id);
            icon.remove_effect_by_name(WHITE_GLYPH_EFFECT);
        }
        this._whiteIcons = null;
    }

    _scanTrayIcons() {
        for (const [key, indicator] of Object.entries(Main.panel.statusArea)) {
            if (!key.startsWith('appindicator-'))
                continue;
            // AppIndicator keeps the icon actor as _icon. A legacy X11 tray
            // icon is a Shell.TrayIcon instead, a window, not an St.Icon:
            // nothing here can recolour it.
            if (indicator?._icon instanceof St.Icon)
                this._watchWhiteIcon(indicator._icon);
        }
    }

    _watchWhiteIcon(icon) {
        if (!icon || this._whiteIcons.has(icon))
            return;
        this._whiteIcons.set(icon, [
            icon.connect('notify::gicon', () => this._syncWhiteIcon(icon)),
            icon.connect('notify::icon-name', () => this._syncWhiteIcon(icon)),
            icon.connect('destroy', () => this._whiteIcons?.delete(icon)),
        ]);
        this._syncWhiteIcon(icon);
    }

    _syncWhiteIcon(icon) {
        const want = !this._isSymbolicIcon(icon);
        const has = icon.get_effect(WHITE_GLYPH_EFFECT) !== null;
        if (want && !has)
            icon.add_effect_with_name(WHITE_GLYPH_EFFECT, new WhiteGlyphEffect());
        else if (!want && has)
            icon.remove_effect_by_name(WHITE_GLYPH_EFFECT);
    }

    // AppIndicator wraps whatever it loaded in an EmblemedIcon. Inside is a
    // ThemedIcon when the name was found in the icon theme, and a FileIcon or
    // a pixbuf when it fell back to the app's own image.
    _isSymbolicIcon(icon) {
        let gicon = icon.gicon;
        if (gicon instanceof Gio.EmblemedIcon)
            gicon = gicon.get_icon();
        const names = gicon instanceof Gio.ThemedIcon ? gicon.get_names()
            : !gicon && icon.icon_name ? [icon.icon_name] : [];
        return names.length > 0 && names[0].endsWith('-symbolic');
    }

    // ---- Panel Menu --------------------------------------------------------

    _buildPanelMenu() {
        this._indicator = new PanelMenu.Button(0.0, 'Aura Glass', false);
        this._icon = new St.Icon({
            icon_name: APP_ICON,
            style_class: 'system-status-icon',
        });
        this._indicator.add_child(this._icon);

        this._statusItem = new PopupMenu.PopupMenuItem('', {reactive: false});
        this._statusItem.setSensitive(false);
        this._indicator.menu.addMenuItem(this._statusItem);
        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._profileItems = {};
        for (const profile of PROFILES) {
            const item = new PopupMenu.PopupImageMenuItem(
                this._profileLabels[profile], PROFILE_ICONS[profile]);
            item.connect('activate', () => this._selectProfile(profile));
            this._profileItems[profile] = item;
            this._indicator.menu.addMenuItem(item);
        }
        this._indicator.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._refreshProfileState();
        });
        this._refreshProfileState();
        Main.panel.addToStatusArea(this.metadata.uuid, this._indicator);
        this._syncTopBarIcon();
    }

    // Hidden rather than destroyed, so the menu's state and _hookWhiteIcons keep
    // the one icon they hold. On the container, after addToStatusArea, because
    // that shows it and it is what holds the panel button's slot.
    _syncTopBarIcon() {
        const shown = readState(TOP_BAR_ICON_FILE) !== '0';
        if (!shown)
            this._indicator.menu.close();
        this._indicator.container.visible = shown;
    }

    _refreshProfileState(statusOverride = null) {
        const profile = readState('adaptive-profile');
        this._profile = PROFILES.includes(profile) ? profile : 'auto';
        const active = readState('adaptive-performance', 'active') === '1';
        const reason = readState('adaptive-performance', 'reason') || 'normal';
        const profileLabel = this._profileLabels?.[this._profile] ?? this._profile;
        let reasonText = reason;
        if (reason === 'full-glass' || reason === 'normal')
            reasonText = '';
        const status = statusOverride ?? (active
            ? `${profileLabel} active — ${reason}`
            : (reasonText ? `${profileLabel} — ${reasonText}` : profileLabel));
        this._setPresentation(status);
    }

    _setPresentation(status) {
        if (this._icon)
            this._icon.icon_name = APP_ICON;
        if (this._statusItem)
            this._statusItem.label.text = status;
        if (!this._profileItems)
            return;
        for (const profile of PROFILES) {
            this._profileItems[profile].setOrnament(profile === this._profile
                ? PopupMenu.Ornament.DOT
                : PopupMenu.Ornament.NONE);
        }
    }

    _selectProfile(profile) {
        this._profile = profile;
        const profileLabel = this._profileLabels?.[profile] ?? profile;
        this._setPresentation(`${profileLabel} — applying…`);
        const local = GLib.build_filenamev([
            GLib.get_home_dir(), '.local', 'bin', 'aura-glass-adaptive']);
        const command = GLib.file_test(local, GLib.FileTest.IS_EXECUTABLE)
            ? local : 'aura-glass-adaptive';
        try {
            const process = Gio.Subprocess.new(
                [command, 'profile', profile],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
            process.wait_check_async(null, (source, result) => {
                try {
                    source.wait_check_finish(result);
                    this._refreshProfileState();
                    this._updateOpacityFromConfig();
                } catch (error) {
                    this._setPresentation(`${profileLabel} — unavailable`);
                }
            });
        } catch (error) {
            this._setPresentation(`${profileLabel} — unavailable`);
        }
    }

    // Blur My Shell ships its own compiled schema rather than a system one,
    // under whichever of these two directories install_bms in
    // lib/steps-extensions.sh put it in — $HOME for the git build this
    // project does by default, /usr/share when a distro package supplied it
    // instead (ext_supports_shell checks the same two places). `trusted:
    // false` is exactly what GNOME Shell's own Extension.getSettings() passes
    // for a schema living in an extension's own directory.
    _openBmsApplicationsSettings() {
        const dirs = [
            GLib.build_filenamev([GLib.get_user_data_dir(), 'gnome-shell',
                'extensions', BMS_UUID, 'schemas']),
            `/usr/share/gnome-shell/extensions/${BMS_UUID}/schemas`,
        ];
        const defaultSource = Gio.SettingsSchemaSource.get_default();
        for (const dir of dirs) {
            if (!GLib.file_test(dir, GLib.FileTest.IS_DIR))
                continue;
            let source;
            try {
                source = Gio.SettingsSchemaSource.new_from_directory(
                    dir, defaultSource, false);
            } catch (e) {
                continue;
            }
            const schema = source.lookup(BMS_SCHEMA_ID, true);
            if (schema)
                return new Gio.Settings({settings_schema: schema});
        }
        return null;
    }

    _appendBlurToggle(menu, window) {
        if (!isBlurrable(window.get_frame_type()))
            return;

        const identity = windowIdentity(window);
        const {classes} = identity;
        if (classes.length === 0)
            return;

        if (!this._isBmsApplicationsActive())
            return;

        // The class this toggle writes into the lists: the rootmost entry in
        // the chain, so right-clicking a dialog toggles the app it belongs
        // to rather than adding the dialog's own (often different, and for
        // some clients absent) class as a new, unrelated entry.
        const wmClass = classes[classes.length - 1];

        // Above Close rather than after it. _buildMenu ends every menu with
        // its own separator then Close, so appending — which is what
        // menu.addAction/addMenuItem do with no position — puts this below
        // Close, one slot from where a click aimed at Close lands instead.
        // The insertion point is found rather than hardcoded to a fixed
        // index: this runs after the real _buildMenu, whose item count
        // varies with the window (a fixed window has no "Restore", a
        // single-workspace session has no "Move to Workspace" items), so the
        // last separator is always the one in front of Close regardless of
        // how many items came before it.
        const items = menu._getMenuItems();
        let closeSeparatorAt = -1;
        for (let i = items.length - 1; i >= 0; i--) {
            if (items[i] instanceof PopupMenu.PopupSeparatorMenuItem) {
                closeSeparatorAt = i;
                break;
            }
        }
        // No separator found at all is a menu shape this has never seen —
        // append rather than guess wrong and land the toggle mid-menu.
        const at = closeSeparatorAt >= 0 ? closeSeparatorAt : items.length;

        const separator = new PopupMenu.PopupSeparatorMenuItem();
        menu.addMenuItem(separator, at);

        // Built by hand rather than through menu.addAction: that override
        // (below) forces Ornament.NONE on every item it creates, and
        // addAction also takes no position argument to insert at.
        const item = new PopupMenu.PopupMenuItem(_('Blur This App'));
        menu.addMenuItem(item, at + 1);

        // Case-insensitive and over the whole chain: a dialog whose own
        // class differs from its parent's is still this app's own window.
        const isSelf = classes.some(
            c => c.toLowerCase() === SELF_WM_CLASS.toLowerCase());
        if (isSelf) {
            // A remove/uncheck here would only undo itself at the next
            // install.sh run — see app_blur_pin_allow.
            item.setOrnament(PopupMenu.Ornament.CHECK);
            item.setSensitive(false);
        } else {
            // enable-all decides which of the two lists is actually consulted
            // right now (apply_app_blur writes both every run regardless) —
            // see the comment above that function in lib/steps-dconf.sh. The
            // checkbox reads the one list scope currently consults, because
            // that is what answers "is this app blurred right now";
            // _toggleBlur below writes both, because "Blur This App" is one
            // choice and a scope flip made later in the settings window
            // should not silently reverse it. Coverage is tested over the
            // whole chain, so a dialog shows checked when the app it belongs
            // to is blurred, matching what check_blur itself now does in
            // Blur My Shell.
            const enableAll = this._settings.get_boolean('enable-all');
            const inWhitelist = matchesAnyRule(this._settings.get_strv('whitelist'), identity);
            const inBlacklist = matchesAnyRule(this._settings.get_strv('blacklist'), identity);
            const checked = inWhitelist || (enableAll && !inBlacklist);

            item.setOrnament(checked ? PopupMenu.Ornament.CHECK
                                      : PopupMenu.Ornament.NONE);
            // The toggle writes classes only, and the allow list wins over the
            // block list, so a title: entry on it keeps this window blurred
            // whatever the toggle does. Greyed out, like the settings window
            // above, rather than offering an uncheck that undoes nothing.
            item.setSensitive(!matchesAnyRule(this._settings.get_strv('whitelist'),
                {classes: [], titles: identity.titles}));
            item.connect('activate', () => {
                this._toggleBlur(wmClass, identity, !checked, item);
            });
        }
    }

    _toggleBlur(wmClass, identity, wantBlurred, item) {
        // A lock wait must never run on GNOME Shell's main loop. The backend
        // reads the current memo after it owns that lock, changes both lists
        // through apply_app_blur, and reports any wildcard it had to remove.
        // Until that succeeds the checkmark stays truthful about live state.
        //
        // The window menu is destroyed when it closes, which is usually long
        // before the backend answers. Touching the item after that logs a
        // "has been already disposed" stack trace into the journal, so every
        // write to it below goes through this guard. The notifications still
        // go out: they are the only feedback once the menu is gone.
        let destroyed = false;
        item.connect('destroy', () => {
            destroyed = true;
        });
        const setSensitive = sensitive => {
            if (!destroyed)
                item.setSensitive(sensitive);
        };
        item.setSensitive(false);
        const local = GLib.build_filenamev([
            GLib.get_home_dir(), '.local', 'bin', 'aura-glass-operation']);
        const command = GLib.file_test(local, GLib.FileTest.IS_EXECUTABLE)
            ? local : 'aura-glass-operation';
        let process;
        try {
            process = Gio.Subprocess.new(
                [command, 'app-blur', '--wm-class', wmClass, '--enabled',
                    wantBlurred ? '1' : '0'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        } catch (error) {
            setSensitive(true);
            Main.notify('aura-glass', `${_('Could not change app blur')}: ${error.message}`);
            return;
        }
        process.communicate_utf8_async(null, null, (source, result) => {
            let ok, _stdout, stderr;
            try {
                [ok, _stdout, stderr] = source.communicate_utf8_finish(result);
            } catch (error) {
                setSensitive(true);
                Main.notify('aura-glass', `${_('Could not change app blur')}: ${error.message}`);
                return;
            }
            if (!ok || !source.get_successful()) {
                setSensitive(true);
                Main.notify('aura-glass', `${_('Could not change app blur')}: ${stderr?.trim() || _('operation failed')}`);
                return;
            }
            // The backend, rather than the menu's old pre-lock list, is now
            // authoritative. Read it only after success so a failed command
            // can never leave a false checkmark behind. Same rule and same
            // class chain as the menu builds its checkmark from above, so a
            // reopened menu never disagrees with this one.
            if (!destroyed) {
                const enableAll = this._settings.get_boolean('enable-all');
                const inWhitelist = matchesAnyRule(this._settings.get_strv('whitelist'), identity);
                const inBlacklist = matchesAnyRule(this._settings.get_strv('blacklist'), identity);
                item.setOrnament(inWhitelist || (enableAll && !inBlacklist)
                    ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
                item.setSensitive(true);
            }
            for (const line of (stderr || '').split('\n')) {
                const match = /^aura-glass-app-blur-wildcard: (always-blur|never-blur): (.+)$/.exec(line);
                if (match) {
                    const list = match[1] === 'never-blur'
                        ? _('the never-blur list') : _('the always-blur list');
                    Main.notify('aura-glass', `${_('Removed from')} ${list}: ${match[2]}`);
                }
            }
        });
    }

    // ---- D-Bus bridge ------------------------------------------------------
    //
    // What the settings window's Per-app blur page cannot otherwise find out:
    // what windows exist right now (ListWindows, for "Open now"). It answers in
    // terms of the same root wm_class the toggle above writes, so a row here and
    // a row on that page are asking about the same thing.

    // wm_class, display name, and how many open windows share it — a browser
    // with six tabs across three windows is one row, not three, because the
    // switch on that row is one choice about the class, not about any one of
    // its windows.
    ListWindows() {
        const tracker = Shell.WindowTracker.get_default();
        const groups = new Map();
        for (const actor of global.get_window_actors()) {
            const window = actor.get_meta_window();
            if (!window || window.is_override_redirect())
                continue;
            if (!isBlurrable(window.get_frame_type()))
                continue;
            if (window.is_skip_taskbar())
                continue;
            const wmClass = rootWindowClass(window);
            if (!wmClass)
                continue;

            let entry = groups.get(wmClass);
            if (!entry) {
                let name = wmClass;
                const app = tracker.get_window_app(window);
                if (app)
                    name = app.get_name();
                else if (window.get_title())
                    name = window.get_title();
                entry = {name, count: 0};
                groups.set(wmClass, entry);
            }
            entry.count += 1;
        }
        return [...groups.entries()].map(
            ([wmClass, {name, count}]) => [wmClass, name, count]);
    }

    GetFocusState() {
        return [Boolean(this._fullscreen), this._focusedWmClass || ''];
    }

    GetFullscreen() {
        return [Boolean(this._fullscreen)];
    }

    InspectOverviewState() {
        return Main.overview.visible ? 'visible' : 'hidden';
    }

    // ---- keeping ListWindows fresh -----------------------------------------

    _trackWindow(window) {
        if (!window || this._destroyIds.has(window))
            return;
        const actor = window.get_compositor_private?.();
        if (actor && this._currentActorOpacity !== undefined && !this._isBmsApplicationsActive()) {
            this._applyWindowActorOpacity(actor, this._currentActorOpacity);
        }
        const id = window.connect('unmanaged', () => {
            this._destroyIds.delete(window);
            this._scheduleWindowsChanged();
        });
        this._destroyIds.set(window, id);
        this._keepUpdateWindowFocus(window);
        this._scheduleWindowsChanged();
    }

    // When the settings window comes back after an update, put the update
    // window in front again. Read once and removed, on the settings window's
    // first show (its wm_class is only known by then). 150 ms after it: the
    // new window's own activation lands first, then this one replaces it.
    _keepUpdateWindowFocus(window) {
        const path = GLib.build_filenamev([GLib.get_user_runtime_dir(),
            KEEP_FOCUS_FILE]);
        if (!GLib.file_test(path, GLib.FileTest.EXISTS))
            return;
        const id = window.connect('shown', () => {
            window.disconnect(id);
            if (!this._destroyIds || window.get_wm_class() !== SELF_WM_CLASS)
                return;
            let pid = 0;
            try {
                const [, bytes] = GLib.file_get_contents(path);
                pid = parseInt(new TextDecoder().decode(bytes), 10);
            } catch {
                return;
            }
            GLib.unlink(path);
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
                const target = global.display.list_all_windows()
                    .find(w => pid > 0 && w.get_pid() === pid);
                if (target)
                    Main.activateWindow(target);
                return GLib.SOURCE_REMOVE;
            });
        });
    }

    // Debounced: a window opening or closing is rarely one event by itself —
    // a browser launch is a splash window replaced by the real one moments
    // later — and firing once per intermediate window would have the
    // settings window's list flicker rather than settle.
    _scheduleWindowsChanged() {
        if (this._windowsChangedTimer)
            GLib.source_remove(this._windowsChangedTimer);
        this._windowsChangedTimer = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, 300, () => {
                this._windowsChangedTimer = 0;
                if (this._dbusImpl)
                    this._dbusImpl.emit_signal('WindowsChanged', null);
                return GLib.SOURCE_REMOVE;
            });
    }

    // ---- Animation speed ------------------------------------------------------

    // GNOME Shell connects its window effects with handlers bound when
    // Main.wm is built, and hardcodes each duration in the ease() call
    // (WINDOW_ANIMATION_TIME and the rest in windowManager.js,
    // POPUP_ANIMATION_TIME in boxpointer.js, ANIMATION_TIME in messageTray.js),
    // so neither a method patch nor a constant can reach them. ease() itself
    // can: every one of those calls goes through Clutter.Actor.prototype.ease,
    // and the actor it is called on says which of the three it is. Opening and
    // closing go through the same calls, so each speed holds both ways.
    _readAnimationSpeeds() {
        this._animationScale = {};
        for (const [kind, file] of Object.entries(ANIMATION_SPEED_FILES)) {
            let speed = parseInt(readState(file), 10);
            if (isNaN(speed) || speed < ANIMATION_SPEED_MIN || speed > ANIMATION_SPEED_MAX)
                speed = ANIMATION_SPEED_SHIPPED;
            this._animationScale[kind] = ANIMATION_SPEED_SHIPPED / speed;
        }
        this._syncEaseHook();
    }

    // Hooked only while a speed is not GNOME's own, so the default costs
    // nothing on the shell's busiest call.
    _syncEaseHook() {
        if (Object.values(this._animationScale).some(scale => scale !== 1))
            this._hookEase();
        else
            this._unhookEase();
    }

    _hookEase() {
        if (this._origEase)
            return;
        const self = this;
        this._sizeChangeClones = new WeakSet();
        this._origEase = Clutter.Actor.prototype.ease;
        Clutter.Actor.prototype.ease = function (props) {
            const scale = self._easeScaleFor(this);
            if (scale !== 1 && typeof props?.duration === 'number')
                props = {...props, duration: Math.round(props.duration * scale)};
            return self._origEase.call(this, props);
        };
        // A maximize or unmaximize fades a still of the old frame out over the
        // window growing in. The still is a bare St.Widget, so it is marked
        // here, where _sizeChangeWindow makes it, to keep it in step with the
        // window. Looked up on Main.wm at call time, so an own property wins.
        const wm = Main.wm;
        if (typeof wm._prepareAnimationInfo === 'function') {
            this._origPrepareAnimationInfo = wm._prepareAnimationInfo;
            wm._prepareAnimationInfo = function (shellwm, actor, ...rest) {
                self._origPrepareAnimationInfo.call(this, shellwm, actor, ...rest);
                const clone = actor?.__animationInfo?.clone;
                if (clone)
                    self._sizeChangeClones.add(clone);
            };
        }
    }

    _unhookEase() {
        if (!this._origEase)
            return;
        Clutter.Actor.prototype.ease = this._origEase;
        this._origEase = null;
        if (this._origPrepareAnimationInfo) {
            delete Main.wm._prepareAnimationInfo;
            this._origPrepareAnimationInfo = null;
        }
        this._sizeChangeClones = null;
    }

    _easeScaleFor(actor) {
        if (actor instanceof Meta.WindowActor || actor instanceof TilePreview ||
            this._sizeChangeClones.has(actor))
            return this._animationScale.window;
        // Every shell menu opens and closes through its BoxPointer: the top
        // bar's, Quick Settings, the calendar, right-click and window menus.
        if (actor instanceof BoxPointer)
            return this._animationScale.menu;
        if (actor === Main.messageTray?._bannerBin)
            return this._animationScale.notification;
        return 1;
    }

    // ---- Fullscreen transition ----------------------------------------------

    // GNOME animates a fullscreen change like a maximize: a still of the old
    // frame scales and fades out over the window growing in. A browser draws
    // fullscreen in two steps: its first buffer at the new size still holds
    // the old page layout, and the page (a video player) lays itself out for
    // the new size a little later. A screencast of YouTube in Chrome put that
    // second step 175-210 ms after the first, inside GNOME's 250 ms, so the
    // change read as a zoom and then a jump: two motions, not one. And the top
    // bar vanishes or reappears at once, as the layout hides it.
    // So on a fullscreen change only, a copy of GNOME's still stays opaque
    // over the window through the same zoom, then cross-fades to the live
    // window, which by then has settled; the browser's in-between frames are
    // never seen. The top bar slides out with it (in, on the way back), at the
    // window's pace. Maximize keeps GNOME's own animation.
    //
    // GNOME's size-change handlers are bound when Main.wm is built, so these
    // run after them on the same signals: at size-change GNOME has made the
    // still (__animationInfo), and at size-changed it has started both eases
    // and thawed the window. Nothing of GNOME's is replaced, so its size-change
    // accounting is untouched. Reduced motion keeps GNOME's cross-fade, which
    // is all it does there.
    _hookFullscreenTransition() {
        this._fullscreenChanges = new WeakMap();
        this._fullscreenCovers = new Map();
        this._panelSlide = null;
        this._sizeChangeIds = [
            global.window_manager.connect('size-change',
                (_wm, actor, change) => this._noteFullscreenChange(actor, change)),
            global.window_manager.connect('size-changed',
                (_wm, actor) => this._runFullscreenTransition(actor)),
        ];
    }

    _unhookFullscreenTransition() {
        for (const id of this._sizeChangeIds ?? [])
            global.window_manager.disconnect(id);
        this._sizeChangeIds = null;
        this._endPanelSlide();
        for (const cover of [...this._fullscreenCovers?.keys() ?? []])
            this._endFullscreenCover(cover);
        this._fullscreenCovers = null;
        this._fullscreenChanges = null;
    }

    _noteFullscreenChange(actor, change) {
        if (change !== Meta.SizeChange.FULLSCREEN && change !== Meta.SizeChange.UNFULLSCREEN)
            return;
        const clone = actor.__animationInfo?.clone;
        if (!clone || St.Settings.get().reducedMotion === St.ReducedMotion.REDUCE)
            return;
        const earlier = this._fullscreenChanges.get(actor);
        if (earlier?.cover)
            this._endFullscreenCover(earlier.cover);
        // Read now, before the layout's fullscreen check hides the bar: by
        // size-changed (the client's new buffer) it may already be gone.
        this._fullscreenChanges.set(actor, {
            change,
            clone,
            panelShown: Main.layoutManager.panelBox.visible,
            cover: this._holdFullscreenCover(actor, actor.__animationInfo.oldRect),
        });
    }

    // Mutter takes GNOME's still and only then flips the window's fullscreen
    // flag, and the window's new size comes from the client later (100-313
    // ms in a screencast). Blur My Shell drops an application's blur, and its
    // see-through, at that flag (unblur-when-fullscreen) and brings them back
    // at the flag on the way out, so for that wait the frozen window showed
    // the other look, and then the cover came in with the first: a flicker
    // of the blur, only on a blurred window. GNOME's still does not help:
    // the window is painted alone offscreen, so a blur in it has nothing
    // behind it to blur.
    // So the cover is taken here, at size-change, from the stage over the
    // window's old frame (what is on screen, blur and all) and goes over the
    // window at once, still opaque, until size-changed starts the zoom
    // (_coverFullscreenChange). It goes with the window, or after
    // FULLSCREEN_WAIT_MS if the new size never comes. If the stage cannot be
    // read, nothing is held and size-changed falls back to GNOME's still.
    _holdFullscreenCover(actor, rect) {
        let content;
        try {
            const scale = global.display.get_monitor_scale(actor.meta_window.get_monitor());
            content = global.stage.paint_to_content(rect, scale, null,
                Clutter.PaintFlag.NO_CURSORS);
        } catch (e) {
            console.warn(`Aura Glass Helper: fullscreen cover not taken: ${e.message}`);
            return null;
        }
        const cover = new St.Widget({
            content,
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
        });
        actor.get_parent().insert_child_above(cover, actor);
        // Direct scanout of the fullscreen window would skip the compositor
        // and so the cover over it. Held off while the cover lives, released
        // in _endFullscreenCover.
        global.compositor.disable_unredirect();
        const hold = {actor, destroyId: 0, waitId: 0};
        this._fullscreenCovers.set(cover, hold);
        hold.destroyId = actor.connect('destroy', () => this._endFullscreenCover(cover));
        hold.waitId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, FULLSCREEN_WAIT_MS, () => {
            hold.waitId = 0;
            this._endFullscreenCover(cover);
            return GLib.SOURCE_REMOVE;
        });
        return cover;
    }

    _runFullscreenTransition(actor) {
        const note = this._fullscreenChanges?.get(actor);
        if (!note)
            return;
        this._fullscreenChanges.delete(actor);
        // Only the size-changed that started GNOME's eases for this still: a
        // later one for the same window finds it gone or another still.
        const info = actor.__animationInfo;
        const held = this._fullscreenCovers?.has(note.cover) ? note.cover : null;
        if (!info || info.clone !== note.clone || info.frozen) {
            if (held)
                this._endFullscreenCover(held);
            return;
        }
        const duration = this._coverFullscreenChange(actor, info, held);

        const window = actor.meta_window;
        const primary = Main.layoutManager.primaryIndex;
        if (Main.overview.visible || window.get_monitor() !== primary)
            return;
        if (note.change === Meta.SizeChange.FULLSCREEN) {
            if (note.panelShown)
                this._slidePanel(true, duration);
            return;
        }
        // Another fullscreen window on the monitor keeps the bar hidden.
        const stillCovered = global.workspace_manager.get_active_workspace().list_windows()
            .some(other => other !== window && other.fullscreen && !other.minimized &&
                other.get_monitor() === primary);
        if (!stillCovered)
            this._slidePanel(false, duration);
    }

    // The cover is the one held since size-change, or else a second widget on
    // GNOME's still (destroyed when its ease ends), eased to the same rect with
    // GNOME's duration and curve, so it stays exactly over the window it hides. It
    // sits just above the window in the window's own group, so it hides the
    // window as GNOME's clone does but stays under the top bar, notifications
    // and OSDs, which it is not meant to hide for the longer hold.
    //
    // The cross-fade does not wait for the zoom: from a maximized window the
    // zoom is only the top bar's height, so holding the still through all of
    // it read as the desktop hanging. It starts FULLSCREEN_SETTLE_MS after the
    // window's new size, just under the browser's second step (175 ms at the
    // earliest), and eases in and out, so a later step (up to 210 ms seen)
    // lands under a cover still above 90% opaque.
    _coverFullscreenChange(actor, info, held) {
        const still = info.clone;
        const target = actor.meta_window.get_frame_rect();
        const source = info.oldRect;
        // Read GNOME's own transition so a changed animation speed is
        // followed. Width does not change between maximized and fullscreen on
        // most monitors, so scale-x may have nothing to ease; look at every
        // property GNOME eases.
        const transition = ['scale-y', 'scale-x', 'translation-y', 'translation-x']
            .map(name => actor.get_transition(name)).find(t => t);
        const duration = transition?.get_duration() ?? this._shadeWindowDuration();

        // The cover held since size-change, its wait over; else one on GNOME's
        // still, the same geometry (_holdFullscreenCover).
        let cover = held;
        if (cover) {
            const hold = this._fullscreenCovers.get(cover);
            if (hold.waitId)
                GLib.source_remove(hold.waitId);
            hold.waitId = 0;
        } else {
            cover = new St.Widget({
                content: still.get_content(),
                x: still.x,
                y: still.y,
                width: still.width,
                height: still.height,
            });
            actor.get_parent().insert_child_above(cover, actor);
            global.compositor.disable_unredirect();
            this._fullscreenCovers.set(cover, {actor, destroyId: 0, waitId: 0});
        }
        still.hide();
        cover.ease({
            x: target.x,
            y: target.y,
            scale_x: target.width / source.width,
            scale_y: target.height / source.height,
            duration,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        });
        // 0.9 of the zoom (225 ms at normal speed): a dissolve this long,
        // eased at both ends, has no visible start or finish, and the whole
        // change still ends about 400 ms after the new size.
        cover.ease({
            opacity: 0,
            delay: FULLSCREEN_SETTLE_MS,
            duration: Math.round(duration * 0.9),
            mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
            onStopped: () => this._endFullscreenCover(cover),
        });
        return duration;
    }

    _endFullscreenCover(cover) {
        const hold = this._fullscreenCovers?.get(cover);
        if (!hold)
            return;
        this._fullscreenCovers.delete(cover);
        if (hold.waitId)
            GLib.source_remove(hold.waitId);
        if (hold.destroyId)
            hold.actor.disconnect(hold.destroyId);
        cover.remove_all_transitions();
        cover.destroy();
        global.compositor.enable_unredirect();
    }

    // The layout hides and shows the bar at its own fullscreen check, which can
    // land before or after the window's new size, and ease() on an unmapped
    // actor jumps straight to the end (environment.js). So the bar slides as a
    // Clutter.Clone on uiGroup both ways: a clone paints its source hidden or
    // not, at the clone's own opacity, and the Blur My Shell panel blur is a
    // child of panelBox, so it goes with it. panelBox itself stays transparent
    // under the clone until the slide ends, so whichever moment the layout
    // picks, only the clone shows.
    // The clone moves and never fades: the window's top edge travels the bar's
    // height in the same time on the same curve, so the bar's bottom edge
    // rides it and no wallpaper opens between them. A screencast with the
    // bar fading as it went showed its icons gone in a third of the slide
    // and an empty strip of wallpaper above the window after that; on the
    // way back, the strip came down before the icons did. duration is the
    // cover's, read from GNOME's zoom, so a changed animation speed keeps the
    // two edges together.
    _slidePanel(out, duration) {
        this._endPanelSlide();
        const panelBox = Main.layoutManager.panelBox;
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor)
            return;
        // panelBox and the clone are both children of uiGroup, so they share
        // its coordinates.
        const distance = panelBox.y + panelBox.height - monitor.y;
        if (distance <= 0)
            return;
        const clone = new Clutter.Clone({
            source: panelBox,
            x: panelBox.x,
            y: panelBox.y,
            width: panelBox.width,
            height: panelBox.height,
            translation_y: out ? 0 : -distance,
        });
        Main.uiGroup.add_child(clone);
        panelBox.opacity = 0;
        // A fullscreen window alone on its monitor can be given direct scanout,
        // which skips the compositor and so the clone over it. Held off for the
        // slide only, and released in _endPanelSlide.
        global.compositor.disable_unredirect();
        this._panelSlide = clone;
        clone.ease({
            translation_y: out ? -distance : 0,
            duration,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onStopped: () => this._endPanelSlide(clone),
        });
    }

    // Puts panelBox back however the slide ended. A slide's own onStopped
    // passes its clone, so a newer slide (a quick toggle back) is not ended
    // by the one it replaced.
    _endPanelSlide(clone) {
        const slide = this._panelSlide;
        if (!slide || (clone !== undefined && clone !== slide))
            return;
        this._panelSlide = null;
        slide.remove_all_transitions();
        slide.destroy();
        Main.layoutManager.panelBox.opacity = 255;
        global.compositor.enable_unredirect();
    }

    // ---- Window actor opacity (live without restart) -----------------------

    _initOpacityMonitor() {
        this._currentActorOpacity = 255;
        this._confMonitors = [];
        this._updateOpacityFromConfig();
        // A directory monitor only reports its direct children, and the
        // adaptive worker's `active` lives one level down in
        // adaptive-performance/, so that directory gets a monitor of its own.
        // With only the top one, a transition never reached this.
        for (const parts of [[], ['adaptive-performance']]) {
            try {
                const dir = Gio.File.new_for_path(configPath(...parts));
                const monitor = dir.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
                const id = monitor.connect('changed', (_mon, file, other, eventType) => {
                    // --reset moves the memos away, and this is the one a
                    // missing file changes something live for: it means shown.
                    if (eventType === Gio.FileMonitorEvent.DELETED ||
                        eventType === Gio.FileMonitorEvent.MOVED_OUT) {
                        if (file?.get_basename() === TOP_BAR_ICON_FILE)
                            this._syncTopBarIcon();
                        return;
                    }
                    if (eventType !== Gio.FileMonitorEvent.CHANGES_DONE_HINT &&
                        eventType !== Gio.FileMonitorEvent.CREATED &&
                        eventType !== Gio.FileMonitorEvent.CHANGED &&
                        eventType !== Gio.FileMonitorEvent.MOVED_IN &&
                        eventType !== Gio.FileMonitorEvent.RENAMED)
                        return;
                    // The worker and the installer write through a temporary
                    // file and rename it over the real one, which arrives as
                    // RENAMED with the real name on the other file.
                    const name = (eventType === Gio.FileMonitorEvent.RENAMED ? other : file)?.get_basename();
                    if (OPACITY_STATE_FILES.has(name))
                        this._updateOpacityFromConfig();
                    else if (name === 'window-menu')
                        this._syncWindowMenu();
                    else if (name === TOP_BAR_ICON_FILE)
                        this._syncTopBarIcon();
                    else if (name === OVERRIDE_SHEET)
                        this._loadOverrideSheet();
                    else if (ANIMATION_SPEED_STATE_FILES.has(name))
                        this._readAnimationSpeeds();
                });
                this._confMonitors.push([monitor, id]);
            } catch (e) {
                // Directory missing (no adaptive run yet) or monitoring unsupported
            }
        }
    }

    _updateOpacityFromConfig() {
        const adaptiveActive = readState('adaptive-performance', 'active') === '1';
        if (adaptiveActive) {
            this.setWindowOpacityAll(255);
            return;
        }

        if (this._isBmsApplicationsActive()) {
            // When Blur My Shell's application blur is active, Blur My Shell manages
            // window actor opacity for whitelisted/blurred apps. Setting all window
            // actors to 255 would overwrite Blur My Shell's transparency and break blur.
            this._currentActorOpacity = undefined;
            return;
        }

        const mode = readState('glass-mode');
        if (mode === 'performance') {
            const opStr = readState('app-opacity');
            let opacity = 252;
            if (opStr) {
                const parsed = parseInt(opStr, 10);
                if (!isNaN(parsed) && parsed >= 0 && parsed <= 255)
                    opacity = parsed;
            } else {
                const trStr = readState('modes', 'performance', 'app-transparency') || readState('app-transparency');
                if (trStr) {
                    const parsed = parseFloat(trStr);
                    if (!isNaN(parsed) && parsed > 0 && parsed <= 1.0)
                        opacity = Math.round(parsed * 255);
                }
            }
            this.setWindowOpacityAll(opacity);
            return;
        }

        this.setWindowOpacityAll(255);
    }

    SetWindowOpacity(opacity) {
        const val = Math.max(0, Math.min(255, opacity));
        if (this._isBmsApplicationsActive()) {
            if (this._settings) {
                try {
                    this._settings.set_int('opacity', val);
                } catch (e) {
                    // ignore if setting failed
                }
            }
            return;
        }
        this.setWindowOpacityAll(val);
    }

    RefreshOpacity() {
        this._updateOpacityFromConfig();
    }

    // Reads the stylesheet again in one step. User Themes can only be made to
    // reload by changing its key, which puts the shell through the default theme
    // on the way; this is what aura-glass-apply asks for first.
    ReloadTheme() {
        Main.loadTheme();
    }

    setWindowOpacityAll(opacity) {
        if (this._isBmsApplicationsActive()) {
            if (this._settings) {
                try {
                    if (this._settings.get_int('opacity') !== opacity)
                        this._settings.set_int('opacity', opacity);
                } catch (e) {
                    // ignore if setting failed
                }
            }
            return;
        }
        this._currentActorOpacity = opacity;
        for (const actor of global.get_window_actors()) {
            this._applyWindowActorOpacity(actor, opacity);
        }
    }

    _applyWindowActorOpacity(actor, opacity) {
        if (!actor)
            return;
        const window = actor.get_meta_window?.();
        if (window && !isBlurrable(window.get_frame_type()))
            return;

        const BLUR_ACTOR_NAMES = new Set(['blur-actor', 'bms-application-blurred-widget']);
        let childUpdated = false;
        actor.get_children?.().forEach(child => {
            if (!BLUR_ACTOR_NAMES.has(child.name)) {
                if (child.opacity !== opacity)
                    child.opacity = opacity;
                childUpdated = true;
            }
        });
        if (!childUpdated && actor.opacity !== opacity)
            actor.opacity = opacity;
    }
}
