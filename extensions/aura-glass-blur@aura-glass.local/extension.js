/* aura-glass window-menu blur toggle, and a small D-Bus bridge for the
 * settings window's per-app blur page.
 *
 * The per-app blur allow/block list Blur My Shell reads is otherwise editable
 * in exactly two places: --app-blur-allow/--app-blur-block on install.sh, and
 * the Per-app blur page in the aura-glass settings window. Both mean leaving
 * the window you actually want to toggle. This puts the same question where
 * it gets asked — right-click the titlebar, "Blur This App" — by monkeypatching
 * WindowMenu._buildMenu the way Just Perfection's screenshotInWindowMenuShow
 * already does in this project's own extension set.
 *
 * Ships no schema of its own. It reads and writes Blur My Shell's
 * org.gnome.shell.extensions.blur-my-shell.applications directly — 'blur',
 * 'enable-all', 'whitelist', 'blacklist' — the same keys apply_app_blur in
 * lib/steps-dconf.sh writes. The menu delegates changes to the operation
 * helper, which acquires the project writer lock and updates those keys plus
 * their memos through that canonical Bash function.
 *
 * Adds nothing at all when Blur My Shell's schema cannot be found, or when
 * applications/blur is off: a menu item that provably does nothing is worse
 * than no menu item.
 *
 * The D-Bus service (io.github.DevWebeloper.AuraGlass) is what the settings
 * window's Per-app blur page uses for "Open now": an unprivileged GTK app has
 * no other way, on Wayland, to know what windows exist. It answers ListWindows,
 * and fires WindowsChanged when the answer to ListWindows would differ. It is
 * exported whenever the extension is enabled, independent of whether Blur My
 * Shell is present — the settings window is what decides whether to call it, by
 * whether the bridge answers at all.
 */

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
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

const DBUS_NAME = 'io.github.DevWebeloper.AuraGlass';
const DBUS_PATH = '/io/github/DevWebeloper/AuraGlass';
const DBUS_IFACE = `
<node>
  <interface name="${DBUS_NAME}">
    <method name="ListWindows">
      <arg type="a(ssu)" direction="out" name="windows"/>
    </method>
    <signal name="WindowsChanged"/>
  </interface>
</node>`;

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
        this._settings = this._openBmsApplicationsSettings();
        if (this._settings) {
            this._origBuildMenu = WindowMenu.prototype._buildMenu;
            const self = this;
            WindowMenu.prototype._buildMenu = function (window) {
                self._origBuildMenu.call(this, window);
                self._appendBlurToggle(this, window);
            };
        }

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
    }

    disable() {
        if (this._origBuildMenu) {
            WindowMenu.prototype._buildMenu = this._origBuildMenu;
            this._origBuildMenu = null;
        }
        this._settings = null;

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

        if (this._nameOwnerId) {
            Gio.bus_unown_name(this._nameOwnerId);
            this._nameOwnerId = 0;
        }
        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
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

        if (!this._settings.get_boolean('blur'))
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
            const scope = this._settings.get_boolean('enable-all') ? 'all' : 'gtk';
            const key = scope === 'all' ? 'blacklist' : 'whitelist';
            const covered = matchesAnyClass(this._settings.get_strv(key), classes);
            const checked = scope === 'all' ? !covered : covered;

            item.setOrnament(checked ? PopupMenu.Ornament.CHECK
                                      : PopupMenu.Ornament.NONE);
            item.connect('activate', () => {
                this._toggleBlur(wmClass, !checked, item);
            });
        }
    }

    _toggleBlur(wmClass, wantBlurred, item) {
        // A lock wait must never run on GNOME Shell's main loop. The backend
        // reads the current memo after it owns that lock, changes both lists
        // through apply_app_blur, and reports any wildcard it had to remove.
        // Until that succeeds the checkmark stays truthful about live state.
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
            item.setSensitive(true);
            Main.notify('aura-glass', `${_('Could not change app blur')}: ${error.message}`);
            return;
        }
        process.communicate_utf8_async(null, null, (source, result) => {
            let ok, _stdout, stderr;
            try {
                [ok, _stdout, stderr] = source.communicate_utf8_finish(result);
            } catch (error) {
                item.setSensitive(true);
                Main.notify('aura-glass', `${_('Could not change app blur')}: ${error.message}`);
                return;
            }
            if (!ok || !source.get_successful()) {
                item.setSensitive(true);
                Main.notify('aura-glass', `${_('Could not change app blur')}: ${stderr?.trim() || _('operation failed')}`);
                return;
            }
            // The backend, rather than the menu's old pre-lock list, is now
            // authoritative. Read it only after success so a failed command
            // can never leave a false checkmark behind.
            const scope = this._settings.get_boolean('enable-all') ? 'all' : 'gtk';
            const key = scope === 'all' ? 'blacklist' : 'whitelist';
            const covered = matchesAny(this._settings.get_strv(key), wmClass);
            item.setOrnament((scope === 'all' ? !covered : covered)
                ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
            item.setSensitive(true);
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

    // ---- keeping ListWindows fresh -----------------------------------------

    _trackWindow(window) {
        if (!window || this._destroyIds.has(window))
            return;
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
}
