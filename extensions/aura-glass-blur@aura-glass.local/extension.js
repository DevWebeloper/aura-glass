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
 * It also shades the top bar while the focused window fills the panel's
 * monitor (PANEL_SHADE_CLASS, painted by css/shell-00-flat.css).
 *
 * It stays installed and enabled in every mode, Performance included.
 */

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {WindowMenu} from 'resource:///org/gnome/shell/ui/windowMenu.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

const BMS_UUID = 'blur-my-shell@aunetx';
const BMS_SCHEMA_ID = 'org.gnome.shell.extensions.blur-my-shell.applications';

// Pinned back onto the whitelist by every install.sh run (app_blur_pin_allow
// in lib/steps-dconf.sh) — the same string is duplicated in
// gui/aura_glass_settings.py (SELF_WM_CLASS) and checked against this one by
// tools/check-app-blur-lists.sh.
const SELF_WM_CLASS = 'io.github.DevWebeloper.AuraGlassSettings';
// The top-bar indicator uses Aura Glass's own application icon rather than
// cycling through profile status glyphs, keeping a recognizable identity in the panel.
const APP_ICON = SELF_WM_CLASS;

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

const PROFILES = ['auto', 'full', 'performance'];
// State files whose change can move the window opacity this extension owns.
const OPACITY_STATE_FILES = new Set([
    'app-opacity', 'app-transparency', 'glass-mode', 'adaptive-performance', 'active',
]);
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

// Mirrors Blur My Shell's own components/applications.js wildcardToRegex:
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

function matchesAny(patterns, wmClass) {
    return patterns.some(p => p.trim() !== '' && wildcardToRegex(p).test(wmClass));
}

function matchesAnyClass(patterns, classes) {
    return classes.some(c => matchesAny(patterns, c));
}

// Mirrors patches/blur-my-shell-subwindows.patch's window_classes: a window's
// own wm_class and GTK application id, then the same two for each window up
// its transient-for chain — so right-clicking a dialog's titlebar toggles the
// app it belongs to, and the checkbox reads as checked when that app is
// blurred, not only when the dialog's own (often different, sometimes empty)
// class happens to be on the list. Bounded and cycle-guarded for the same
// reason the patch's copy is: transient-for loops are malformed but a client
// can still set one.
function windowClasses(window) {
    const classes = [];
    const push = v => { if (v && !classes.includes(v)) classes.push(v); };

    push(window.get_wm_class());
    push(window.get_gtk_application_id());

    const seen = new Set([window]);
    let parent = window.get_transient_for();
    for (let depth = 0; parent && depth < 8 && !seen.has(parent); depth++) {
        seen.add(parent);
        push(parent.get_wm_class());
        push(parent.get_gtk_application_id());
        parent = parent.get_transient_for();
    }
    return classes;
}

// The root class a window belongs to, for both the window-menu toggle and the
// D-Bus bridge: the last entry in the transient-for chain, so a dialog
// resolves to the app it belongs to rather than to its own (often different,
// sometimes absent) class.
function rootWindowClass(window) {
    const classes = windowClasses(window);
    return classes.length ? classes[classes.length - 1] : null;
}

// Mirrors coversMonitor in patches/blur-my-shell-static-maximized.patch, so the
// top bar shades for exactly the windows Blur My Shell treats as filling the
// screen: maximized both ways, fullscreen, or sized over the whole work area
// without either flag. The last is Tiling Assistant's drag-to-top or maximize
// with maximize-with-gap on: it resizes to the work area instead of
// maximizing, so GTK never sees the window as maximized either.
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

// The same frame-type gate check_blur applies in Blur My Shell's
// components/applications.js (patched by patches/blur-my-shell-subwindows.patch
// to include ATTACHED and UTILITY too) — a window neither this nor Blur My
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

        // The overview gives the top bar its own look, so the shade lifts
        // while it is open and comes back with the window when it closes.
        this._overviewIds = [
            Main.overview.connect('showing', () => this._syncPanelShade(true)),
            Main.overview.connect('hidden', () => this._syncPanelShade(false)),
        ];
        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._syncPanelShade());

        this._focusWindowId = global.display.connect(
            'focus-window', (_display, window) => this._watchFocusedWindow(window));
        this._watchFocusedWindow(global.display.focusWindow ?? global.display.focus_window);

        this._buildPanelMenu();
        this._initOpacityMonitor();
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

        if (!this._isBmsApplicationsActive()) {
            this.setWindowOpacityAll(255);
        }

        this._unhookWindowMenu();
        this._settings = null;

        if (this._focusWindowId) {
            global.display.disconnect(this._focusWindowId);
            this._focusWindowId = 0;
        }
        this._watchFocusedWindow(null);

        for (const id of this._overviewIds ?? [])
            Main.overview.disconnect(id);
        this._overviewIds = null;
        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = 0;
        }

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
                    this._syncPanelShade();
                });
            // size-changed and position-changed catch a tiler's resize to the
            // work area and a move to another monitor, which set no flag.
            this._focusedWindowGeometryIds = [
                'notify::maximized-horizontally',
                'notify::maximized-vertically',
                'size-changed',
                'position-changed',
            ].map(signal => this._focusedWindow.connect(
                signal, () => this._syncPanelShade()));
        }
        this._updateFocusState();
        this._syncPanelShade();
    }

    // The panel lives on the primary monitor, so a window filling another
    // monitor leaves it alone.
    _syncPanelShade(overviewVisible = Main.overview.visible) {
        const window = this._focusedWindow;
        const shade = Boolean(window) && !overviewVisible &&
            window.get_monitor() === Main.layoutManager.primaryIndex &&
            coversMonitor(window);
        if (shade)
            Main.panel.add_style_class_name(PANEL_SHADE_CLASS);
        else
            Main.panel.remove_style_class_name(PANEL_SHADE_CLASS);
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

        const classes = windowClasses(window);
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
            const inWhitelist = matchesAnyClass(this._settings.get_strv('whitelist'), classes);
            const inBlacklist = matchesAnyClass(this._settings.get_strv('blacklist'), classes);
            const checked = inWhitelist || (enableAll && !inBlacklist);

            item.setOrnament(checked ? PopupMenu.Ornament.CHECK
                                      : PopupMenu.Ornament.NONE);
            item.connect('activate', () => {
                this._toggleBlur(wmClass, classes, !checked, item);
            });
        }
    }

    _toggleBlur(wmClass, classes, wantBlurred, item) {
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
                const inWhitelist = matchesAnyClass(this._settings.get_strv('whitelist'), classes);
                const inBlacklist = matchesAnyClass(this._settings.get_strv('blacklist'), classes);
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
        this._scheduleWindowsChanged();
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
