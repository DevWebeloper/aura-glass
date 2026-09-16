/* Aura Glass's always-available adaptive profile panel control.
 *
 * The normal blur resolver remains install.sh.  This extension only starts
 * aura-glass-adaptive with one selected profile; the worker samples the
 * session and asks that resolver for a transient active/restore operation.
 * Keeping the command asynchronous is important: an operation may wait for
 * the shared Aura Glass writer lock and must never stall GNOME Shell's UI.
 *
 * The same extension publishes whether the focused Meta window is fullscreen.
 * The worker treats an absent D-Bus owner as no fullscreen trigger, so a
 * disabled, not-yet-loaded, or unavailable extension cannot make the service
 * fail or leave the panel unusable.
 */

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const DBUS_NAME = 'io.github.DevWebeloper.AuraGlass.Adaptive';
const DBUS_PATH = '/io/github/DevWebeloper/AuraGlass/Adaptive';
const DBUS_IFACE = `
<node>
  <interface name="io.github.DevWebeloper.AuraGlass.Adaptive1">
    <method name="GetFullscreen">
      <arg type="b" direction="out" name="fullscreen"/>
    </method>
    <signal name="FullscreenChanged">
      <arg type="b" name="fullscreen"/>
    </signal>
  </interface>
</node>`;

const PROFILES = ['auto', 'full', 'performance'];
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

export default class AuraGlassAdaptiveExtension extends Extension {
    enable() {
        this._ = str => this.gettext(str);
        this._profileLabels = {
            auto: this._('Auto'),
            full: this._('Full Glass'),
            performance: this._('Performance'),
        };
        this._reasonLabels = {
            battery: this._('battery power'),
            fullscreen: this._('fullscreen'),
            gpu: this._('GPU load'),
            'full-glass': this._('full glass'),
            solid: this._('solid mode'),
            normal: this._('normal'),
            performance: this._('performance'),
        };

        this._fullscreen = false;
        this._focusedWindow = null;
        this._focusedWindowFullscreenId = 0;

        this._dbusImpl = Gio.DBusExportedObject.wrapJSObject(DBUS_IFACE, this);
        this._dbusImpl.export(Gio.DBus.session, DBUS_PATH);
        this._nameOwnerId = Gio.bus_own_name(
            Gio.BusType.SESSION, DBUS_NAME, Gio.BusNameOwnerFlags.NONE,
            null, null, null);

        this._focusWindowId = global.display.connect(
            'focus-window', (_display, window) => this._watchFocusedWindow(window));
        this._watchFocusedWindow(global.display.focusWindow ?? global.display.focus_window);

        this._indicator = new PanelMenu.Button(0.0, this.metadata.name, false);
        this._icon = new St.Icon({
            style_class: 'system-status-icon',
        });
        this._indicator.add_child(this._icon);
        this._buildMenu();
        this._refreshState();
        Main.panel.addToStatusArea(this.metadata.uuid, this._indicator);
    }

    disable() {
        if (this._focusWindowId) {
            global.display.disconnect(this._focusWindowId);
            this._focusWindowId = 0;
        }
        this._watchFocusedWindow(null);

        if (this._nameOwnerId) {
            Gio.bus_unown_name(this._nameOwnerId);
            this._nameOwnerId = 0;
        }
        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
        }
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
        this._icon = null;
        this._statusItem = null;
        this._profileItems = null;
        this._profileLabels = null;
        this._reasonLabels = null;
    }

    // D-Bus calls return a single-element array for the one out parameter.
    GetFullscreen() {
        return [this._fullscreen];
    }

    _watchFocusedWindow(window) {
        if (this._focusedWindow && this._focusedWindowFullscreenId) {
            this._focusedWindow.disconnect(this._focusedWindowFullscreenId);
            this._focusedWindowFullscreenId = 0;
        }
        this._focusedWindow = window ?? null;
        if (this._focusedWindow) {
            this._focusedWindowFullscreenId = this._focusedWindow.connect(
                'notify::fullscreen', () => {
                    if (this._focusedWindow)
                        this._setFullscreen(Boolean(this._focusedWindow.fullscreen));
                });
        }
        this._setFullscreen(Boolean(this._focusedWindow?.fullscreen));
    }

    _setFullscreen(fullscreen) {
        if (fullscreen === this._fullscreen)
            return;
        this._fullscreen = fullscreen;
        if (this._dbusImpl) {
            this._dbusImpl.emit_signal('FullscreenChanged',
                new GLib.Variant('(b)', [fullscreen]));
        }
    }

    _buildMenu() {
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
                this._refreshState();
        });
    }

    _refreshState(statusOverride = null) {
        const profile = readState('adaptive-profile');
        this._profile = PROFILES.includes(profile) ? profile : 'auto';
        const active = readState('adaptive-performance', 'active') === '1';
        const reason = readState('adaptive-performance', 'reason') || 'normal';
        const reasonLabel = this._reasonLabels?.[reason] ?? reason;
        const profileLabel = this._profileLabels?.[this._profile] ?? this._profile;
        const status = statusOverride ?? (active
            ? this._('%s active — %s').format(profileLabel, reasonLabel)
            : this._('%s — %s').format(profileLabel, reasonLabel));
        this._setPresentation(status);
    }

    _setPresentation(status) {
        if (this._icon)
            this._icon.icon_name = PROFILE_ICONS[this._profile];
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
        this._setPresentation(this._('%s — applying…').format(profileLabel));
        const command = GLib.build_filenamev([
            GLib.get_home_dir(), '.local', 'bin', 'aura-glass-adaptive',
        ]);
        try {
            const process = Gio.Subprocess.new(
                [command, 'profile', profile],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
            process.wait_check_async(null, (source, result) => {
                try {
                    source.wait_check_finish(result);
                    this._refreshState();
                } catch (error) {
                    this._setPresentation(this._('%s — unavailable').format(profileLabel));
                }
            });
        } catch (error) {
            // A settings-only install can race an existing Shell session. The
            // menu remains responsive and reports the missing launcher instead
            // of letting an absent helper break the panel.
            this._setPresentation(this._('%s — unavailable').format(profileLabel));
        }
    }
}
