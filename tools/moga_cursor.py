#!/usr/bin/env python3
"""Resolve Aura Glass accents to Moyash's official Moga Neon releases."""

import json
import sys
from urllib.parse import unquote


VARIANTS = {
    "blue": ("Blue", "Moga-Neon-Blue.zip", "d193a5cf9a38478165c4a9f41fdacd18"),
    "teal": ("Cyan", "Moga-Neon-Cyan.zip", "e0a1ff78c6b6b9f7248873b70002a2ba"),
    "green": ("Green", "Moga-Neon-Green.zip", "25e9a0f4df1f2bd4b749d687c2810c63"),
    "yellow": ("Yellow", "Moga-Neon-Yellow.zip", "acef804aa6e3e61e04bd931030753c2b"),
    "orange": ("Orange", "Moga-Neon-Orange.zip", "0ccc899ec383367afee017d30b67e203"),
    "red": ("Red", "Moga-Neon-Red.zip", "b3745d8268a8e790bba2996438dd4f53"),
    "pink": ("Rose", "Moga-Neon-Rose.zip", "834fe75fa3c513cc418aad96cd4fafb8"),
    "purple": ("Purple", "Moga-Neon-Purple.zip", "6ec7f0cc041c2aca32561493dd002763"),
    "slate": ("Sky", "Moga-Neon-Sky.zip", "41d45aed9191f4f252fdc8c71878c3a0"),
}


def variant_for(accent):
    try:
        return VARIANTS[accent][0]
    except KeyError as exc:
        raise ValueError("unknown Aura Glass accent: %s" % accent) from exc


def resolve(accent, metadata_path):
    variant, archive, expected_md5 = VARIANTS.get(accent, (None, None, None))
    if variant is None:
        raise ValueError("unknown Aura Glass accent: %s" % accent)

    try:
        with open(metadata_path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        raise ValueError("could not read Moga source metadata: %s" % exc) from exc

    entries = [item for item in payload.get("files", [])
               if item.get("name") == archive]
    if len(entries) != 1:
        raise ValueError("Moga metadata has %d entries named %s; expected one"
                         % (len(entries), archive))
    entry = entries[0]
    if str(entry.get("active")) != "1":
        raise ValueError("Moga release %s is not active" % archive)
    if entry.get("md5sum") != expected_md5:
        raise ValueError("Moga release %s has an unexpected MD5" % archive)
    encoded_url = entry.get("url")
    if not encoded_url:
        raise ValueError("Moga release %s has no download URL" % archive)
    return variant, archive, expected_md5, unquote(encoded_url)


def main(argv):
    if len(argv) == 3 and argv[1] == "variant":
        print(variant_for(argv[2]))
        return 0
    if len(argv) == 4 and argv[1] == "resolve":
        print("\t".join(resolve(argv[2], argv[3])))
        return 0
    print("usage: moga_cursor.py variant ACCENT | resolve ACCENT METADATA_JSON",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except ValueError as exc:
        print("moga_cursor: %s" % exc, file=sys.stderr)
        raise SystemExit(1)
