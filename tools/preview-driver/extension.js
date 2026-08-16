/* aura-glass preview driver
 *
 * Most of this project's shell CSS paints surfaces you cannot see on an idle
 * desktop: quick settings, the date menu, notifications, dialogs, the OSD.
 * Screenshotting them needs something to open them, and on GNOME 50 there is
 * nothing to hand — org.gnome.Shell.Eval answers (false, '') and there is no
 * UnsafeMode property to turn it back on. So the preview session loads this,
 * which exposes exactly the openings it needs on its own D-Bus name.
 *
 * This is a testing tool and belongs only in the profile tools/preview.sh
 * builds. It is deliberately not installed by install.sh: it lets anything on
 * the session bus open shell menus, which is fine on a private bus holding one
 * throwaway shell and not fine on a desktop you actually use.
 */

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ModalDialog from 'resource:///org/gnome/shell/ui/modalDialog.js';
import * as AltTab from 'resource:///org/gnome/shell/ui/altTab.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `
<node>
  <interface name="org.auraGlass.PreviewDriver">
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
    <method name="ShowDialog">
      <arg type="s" direction="in" name="title"/>
      <arg type="s" direction="in" name="body"/>
    </method>
    <method name="HideDialog"/>
    <method name="ShowSwitcher"/>
    <method name="HideSwitcher"/>
  </interface>
</node>`;

export default class PreviewDriverExtension extends Extension {
    enable() {
        this._dialog = null;
        this._switcher = null;
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, '/org/auraGlass/PreviewDriver');
        // Owning a name as well as exporting the object gives the harness
        // something to wait for: it can poll for the name instead of sleeping
        // and hoping the extension finished loading.
        this._nameId = Gio.bus_own_name(
            Gio.BusType.SESSION, 'org.auraGlass.PreviewDriver',
            Gio.BusNameOwnerFlags.REPLACE, null, null, null);
    }

    disable() {
        this.HideDialog();
        if (this._nameId) {
            Gio.bus_unown_name(this._nameId);
            this._nameId = null;
        }
        this._dbus?.unexport();
        this._dbus = null;
    }

    Ping() {
        return 'aura-glass preview driver';
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

    // css/shell-50-dialogs.css had no coverage at all, because the surfaces it
    // paints are the log-out and power-off dialogs and those cannot be opened
    // without actually logging out. A real end-session dialog is a ModalDialog
    // carrying the 'end-session-dialog' style class, so building one directly
    // renders the same tree against the same selectors — .modal-dialog from the
    // widget itself, .end-session-dialog from the class, and the button ladder
    // including :default from addButton.
    //
    // Nothing here talks to the session manager, so there is no path from this
    // to an actual log out. It is the dialog's appearance, not its behaviour.
    ShowDialog(title, body) {
        this.HideDialog();

        const dialog = new ModalDialog.ModalDialog({
            styleClass: 'end-session-dialog',
            destroyOnClose: false,
        });

        const box = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            style_class: 'message-dialog-content',
        });
        box.add_child(new St.Label({
            text: title || 'Restart',
            style_class: 'message-dialog-title',
        }));
        box.add_child(new St.Label({
            text: body || 'The system will restart automatically.',
            style_class: 'message-dialog-description',
        }));
        dialog.contentLayout.add_child(box);

        // Two buttons, one of them default, so the dialog exercises both the
        // plain control fill and the accent one the sheet paints on :default.
        dialog.addButton({
            label: 'Cancel',
            key: Clutter.KEY_Escape,
            action: () => this.HideDialog(),
        });
        dialog.addButton({
            label: 'Restart',
            default: true,
            action: () => this.HideDialog(),
        });

        dialog.open(global.get_current_time());
        this._dialog = dialog;
    }

    HideDialog() {
        if (!this._dialog)
            return;
        const dialog = this._dialog;
        this._dialog = null;
        dialog.close(global.get_current_time());
        // close() only fades it out; destroyOnClose is off so that a failed
        // close cannot leave a half-torn-down actor behind mid-screenshot.
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            dialog.destroy();
            return GLib.SOURCE_REMOVE;
        });
    }

    ShowSwitcher() {
        this.HideSwitcher();
        const popup = new AltTab.AppSwitcherPopup();
        if (popup.show(false, 'switch-applications', 0)) {
            this._switcher = popup;
        }
    }

    HideSwitcher() {
        if (!this._switcher)
            return;
        const switcher = this._switcher;
        this._switcher = null;
        switcher.fadeAndDestroy();
    }
}
