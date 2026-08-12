/* tahoe-glass preview driver
 *
 * Most of this project's shell CSS paints surfaces you cannot see on an idle
 * desktop: quick settings, the date menu, notifications, the OSD. Screenshotting
 * them needs something to open them, and on GNOME 50 there is nothing to hand —
 * org.gnome.Shell.Eval answers (false, '') and there is no UnsafeMode property
 * to turn it back on. So the preview session loads this, which exposes exactly
 * the openings it needs on its own D-Bus name.
 *
 * This is a testing tool and belongs only in the profile tools/preview.sh
 * builds. It is deliberately not installed by install.sh: it lets anything on
 * the session bus open shell menus, which is fine on a private bus holding one
 * throwaway shell and not fine on a desktop you actually use.
 */

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `
<node>
  <interface name="org.tahoeGlass.PreviewDriver">
    <method name="Ping">
      <arg type="s" direction="out" name="pong"/>
    </method>
    <method name="OpenQuickSettings"/>
    <method name="OpenDateMenu"/>
    <method name="CloseMenus"/>
    <method name="Notify">
      <arg type="s" direction="in" name="title"/>
      <arg type="s" direction="in" name="body"/>
    </method>
    <method name="ShowOsd">
      <arg type="s" direction="in" name="iconName"/>
      <arg type="d" direction="in" name="level"/>
    </method>
    <method name="HideOsd"/>
  </interface>
</node>`;

export default class PreviewDriverExtension extends Extension {
    enable() {
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, '/org/tahoeGlass/PreviewDriver');
        // Owning a name as well as exporting the object gives the harness
        // something to wait for: it can poll for the name instead of sleeping
        // and hoping the extension finished loading.
        this._nameId = Gio.bus_own_name(
            Gio.BusType.SESSION, 'org.tahoeGlass.PreviewDriver',
            Gio.BusNameOwnerFlags.REPLACE, null, null, null);
    }

    disable() {
        if (this._nameId) {
            Gio.bus_unown_name(this._nameId);
            this._nameId = null;
        }
        this._dbus?.unexport();
        this._dbus = null;
    }

    Ping() {
        return 'tahoe-glass preview driver';
    }

    // Opened through the indicator's own menu object rather than by faking a
    // click, so the result is the same tree the shell builds normally — the
    // CSS under test keys off those style classes.
    OpenQuickSettings() {
        Main.panel.statusArea.quickSettings?.menu.open();
    }

    OpenDateMenu() {
        Main.panel.statusArea.dateMenu?.menu.open();
    }

    CloseMenus() {
        Main.panel.statusArea.quickSettings?.menu.close();
        Main.panel.statusArea.dateMenu?.menu.close();
    }

    Notify(title, body) {
        Main.notify(title, body);
    }

    // showAll rather than showOne: the preview runs on a single virtual
    // monitor, but showAll does not need to be told which index that is.
    ShowOsd(iconName, level) {
        const icon = Gio.ThemedIcon.new(
            iconName || 'audio-volume-high-symbolic');
        Main.osdWindowManager.showAll(icon, null, level, 1.0);
    }

    HideOsd() {
        Main.osdWindowManager.hideAll();
    }
}
