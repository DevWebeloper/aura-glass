#!/usr/bin/env python3
"""Report which extensions the preview shell actually loaded.

Worth a script of its own because a shell that silently loaded none of them
renders a plausible-looking stock desktop, and the screenshots give you no hint
that the thing you meant to test was never enabled. That happened twice while
this harness was being written — once because the live session had left
$XDG_RUNTIME_DIR/gnome-shell-disable-extensions lying around, and once because
dconf writes were being dropped.
"""
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

# GNOME 50 reports `enabled` (boolean) and `error` (string) per extension.
# There is no `state` key any more — an earlier version of this script looked
# for one and reported every extension as failed while they were all working,
# which is exactly the kind of false alarm it exists to prevent.
def main():
    wanted = sys.argv[1:]
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    try:
        (info,) = bus.call_sync(
            "org.gnome.Shell", "/org/gnome/Shell",
            "org.gnome.Shell.Extensions", "ListExtensions",
            None, GLib.VariantType("(a{sa{sv}})"),
            Gio.DBusCallFlags.NONE, 10000, None).unpack()
    except GLib.Error as e:
        print("   could not ask the shell: %s" % e.message)
        return 1

    bad = 0
    for uuid in wanted:
        entry = info.get(uuid)
        if entry is None:
            print("   %-52s NOT INSTALLED" % uuid)
            bad += 1
            continue
        err = str(entry.get("error") or "").strip()
        enabled = bool(entry.get("enabled"))
        if enabled and not err:
            print("   %-52s enabled" % uuid)
            continue
        bad += 1
        print("   %-52s %s" % (uuid, "ERROR" if err else "not enabled"))
        if err:
            print("       %s" % err.splitlines()[0])
    if bad:
        print("   -- %d of %d did not load; the screenshots below are not the "
              "full theme" % (bad, len(wanted)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
