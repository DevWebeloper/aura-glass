#!/usr/bin/env python3
"""Screenshot the shell running on this D-Bus session.

GNOME 50's screenshot service answers only callers whose bus name is in its own
allow-list. From /org/gnome/shell/ui/screenshot.js, as shipped in
libshell-18.so:

    this._senderChecker = new DBusSenderChecker([
        'org.gnome.SettingsDaemon.MediaKeys',
        'org.freedesktop.impl.portal.desktop.gnome',
    ]);

Anything else gets `AccessDenied: Screenshot is not allowed`, and there is no
setting that lifts it. So this owns the first of those names and calls from the
same connection.

That is fair game here and nowhere else: tools/preview.sh runs this inside a
bus created by dbus-run-session, holding one throwaway shell and nothing else.
gnome-settings-daemon is not on that bus, so the name is unowned and taking it
displaces nothing. Pointed at a real session bus it would be taking a name the
desktop depends on — so don't.
"""
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.gnome.SettingsDaemon.MediaKeys"


def main():
    if len(sys.argv) != 2:
        print("usage: preview-shot.py OUTPUT.png", file=sys.stderr)
        return 2
    out = sys.argv[1]

    loop = GLib.MainLoop()
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    rc = {"v": 1}

    def acquired(connection, _name):
        try:
            ok, path = connection.call_sync(
                "org.gnome.Shell", "/org/gnome/Shell/Screenshot",
                "org.gnome.Shell.Screenshot", "Screenshot",
                GLib.Variant("(bbs)", (False, False, out)),
                GLib.VariantType("(bs)"),
                Gio.DBusCallFlags.NONE, 30000, None).unpack()
            if ok:
                print(path)
                rc["v"] = 0
            else:
                print("the shell declined to write %s" % out, file=sys.stderr)
        except GLib.Error as e:
            print("screenshot failed: %s" % e.message, file=sys.stderr)
        loop.quit()

    def lost(_connection, name):
        # On the preview's own bus this means the shell is gone, not that a
        # settings daemon beat us to it.
        print("could not take the name %s" % name, file=sys.stderr)
        loop.quit()

    Gio.bus_own_name_on_connection(
        bus, NAME, Gio.BusNameOwnerFlags.NONE, acquired, lost)
    loop.run()
    return rc["v"]


if __name__ == "__main__":
    sys.exit(main())
