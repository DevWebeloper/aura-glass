# Moga Official Accent Cursors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Moyash's official Moga Neon cursor variants as an Aura Glass
pointer pack that follows the selected GNOME accent.

**Architecture:** `tools/moga_cursor.py` is the only source for the nine
Aura Glass accent-to-Moga mappings and the matching active-release MD5 values.
`lib/steps-assets.sh` asks that resolver for a variant, obtains the short-lived
official download URL from the product metadata, verifies the publisher's MD5,
and installs only the needed variant under Aura Glass-owned icon directories.
The installer remains the sole owner of flag resolution and gsettings writes;
the GUI and wizard merely emit `--cursors moga`.

**Tech Stack:** Bash, Python 3 standard library, GNOME gsettings, curl, unzip,
Xcursor themes.

**Spec:** `docs/superpowers/specs/2026-09-15-moga-accent-cursor-design.md`

## Global Constraints

- Support exactly `blue→Blue`, `teal→Cyan`, `green→Green`, `yellow→Yellow`,
  `orange→Orange`, `red→Red`, `pink→Rose`, `purple→Purple`, and `slate→Sky`.
- Install only official Moga Neon archives from
  `https://www.gnome-look.org/p/2302110/loadFiles`; never bundle or recolour
  Moyash's Xcursor artwork.
- The resolver must require an active source-metadata entry whose exact filename
  and published MD5 equal its fixed release manifest before accepting its URL.
- Generated themes live only at
  `~/.local/share/icons/Aura-Glass-Moga-<Variant>`; never touch a standalone
  `Moga-*` directory owned by the user.
- Use `run` for filesystem mutations, preserve the cursor-size unless
  `--cursor-size` is explicit, and never hand-edit generated GTK/theme CSS.
- `--settings-only --accent <name>` must install/select the corresponding Moga
  variant when the remembered pointer pack is `moga`, without requiring the
  caller to repeat `--cursors moga`.
- Credit Moyash and link the official profile in `README.md`.

---

## File Structure

| Path | Responsibility |
|---|---|
| `tools/moga_cursor.py` | Resolve an Aura Glass accent to an official Moga release and validate product metadata. |
| `tools/check-moga-cursors.sh` | Fixture-based regression test for release selection, metadata rejection, and installer dry-run acceptance. |
| `lib/common.sh` | Shared MD5-verified ZIP fetcher used only because Moga publishes MD5 checksums. |
| `lib/steps.sh` | Moga product-page constant. |
| `lib/steps-assets.sh` | Install an official Moga variant and resolve its Aura Glass-owned theme directory. |
| `install.sh`, `lib/steps-dconf.sh` | Accept `moga`, refresh it on accent changes, and select it through gsettings. |
| `gui/aura_glass_settings.py`, `gui/aura_glass_setup_wizard.py` | Offer Moga without duplicating the mapping. |
| `tools/check-gui-flags.py`, `tools/check-wizard-flags.py` | Assert GUI/wizard argument composition and source link parity. |
| `uninstall.sh`, `README.md`, `docs/CONFIG-REFERENCE.md`, `docs/ARCHITECTURE.md` | Lifecycle ownership, user documentation, and attribution. |

### Task 1: Official Moga release resolver

**Files:**
- Create: `tools/moga_cursor.py`
- Create: `tools/check-moga-cursors.sh`

**Interfaces:**
- Produces: `python3 tools/moga_cursor.py variant ACCENT`, printing one of
  `Blue`, `Cyan`, `Green`, `Yellow`, `Orange`, `Red`, `Rose`, `Purple`, `Sky`.
- Produces: `python3 tools/moga_cursor.py resolve ACCENT METADATA_JSON`,
  printing `VARIANT<TAB>ARCHIVE_NAME<TAB>MD5<TAB>DECODED_URL` only after the
  selected active source entry matches the fixed manifest.
- Consumes later: `moga_cursor_theme` and `install_moga_cursors` in
  `lib/steps-assets.sh`.

- [ ] **Step 1: Write the failing resolver checker**

Create a shell checker that writes a JSON fixture with active entries for these
nine exact records, invokes the resolver for every accent, and asserts the
four tab-delimited fields:

```bash
declare -A expected=(
  [blue]='Blue|Moga-Neon-Blue.zip|d193a5cf9a38478165c4a9f41fdacd18'
  [teal]='Cyan|Moga-Neon-Cyan.zip|e0a1ff78c6b6b9f7248873b70002a2ba'
  [green]='Green|Moga-Neon-Green.zip|25e9a0f4df1f2bd4b749d687c2810c63'
  [yellow]='Yellow|Moga-Neon-Yellow.zip|acef804aa6e3e61e04bd931030753c2b'
  [orange]='Orange|Moga-Neon-Orange.zip|0ccc899ec383367afee017d30b67e203'
  [red]='Red|Moga-Neon-Red.zip|b3745d8268a8e790bba2996438dd4f53'
  [pink]='Rose|Moga-Neon-Rose.zip|834fe75fa3c513cc418aad96cd4fafb8'
  [purple]='Purple|Moga-Neon-Purple.zip|6ec7f0cc041c2aca32561493dd002763'
  [slate]='Sky|Moga-Neon-Sky.zip|41d45aed9191f4f252fdc8c71878c3a0'
)
```

Include fixture mutations that make Purple inactive, change Cyan's MD5, and
remove Sky; each `resolve` call must fail without outputting a URL. Also assert
`bash install.sh --settings-only --dry-run --cursors moga --accent teal -y`
fails before the feature exists because `moga` is not yet accepted.

- [ ] **Step 2: Run the checker to verify RED**

Run: `bash tools/check-moga-cursors.sh`

Expected: FAIL because `tools/moga_cursor.py` does not exist and `install.sh`
rejects `--cursors moga`.

- [ ] **Step 3: Implement the standard-library resolver**

Create `tools/moga_cursor.py` with:

```python
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
```

`variant` rejects an unknown accent with a clear stderr message. `resolve`
loads the given JSON file, selects only an entry with `active == "1"`, exact
`name`, exact `md5sum`, and a nonempty `url`, decodes its URL with
`urllib.parse.unquote`, and prints the four fields. Do not accept a second
same-named entry: fail as ambiguous instead.

- [ ] **Step 4: Run the resolver checker to verify GREEN**

Run: `bash tools/check-moga-cursors.sh`

Expected: resolver fixture assertions pass; the installer dry-run assertion
continues to report the expected pre-integration `moga` rejection.

- [ ] **Step 5: Commit the resolver test and implementation**

```bash
git add tools/moga_cursor.py tools/check-moga-cursors.sh
git commit -m "feat(assets): resolve official Moga cursor variants"
```

### Task 2: Installer-owned Moga lifecycle

**Files:**
- Modify: `lib/common.sh:259-282`
- Modify: `lib/steps.sh:105-110`
- Modify: `lib/steps-assets.sh:335-409`
- Modify: `install.sh:112,216-220,707-729,968-983,1396-1403`
- Modify: `lib/steps-dconf.sh:1028-1066`
- Modify: `tools/check-moga-cursors.sh`

**Interfaces:**
- Consumes: `tools/moga_cursor.py variant` and `resolve` from Task 1.
- Produces: `moga_cursor_theme ACCENT`, printing
  `Aura-Glass-Moga-<Variant>`.
- Produces: `install_moga_cursors`, which installs only the resolved official
  archive and leaves an Xcursor directory at the name returned by
  `moga_cursor_theme`.
- Consumes later: GUI `--cursors moga` emissions from Task 3.

- [ ] **Step 1: Extend the failing checker for lifecycle behavior**

Add source assertions and dry-run cases to `tools/check-moga-cursors.sh`:

```bash
dry="$(bash "$ROOT/install.sh" --settings-only --dry-run --cursors moga \
      --accent teal -y 2>&1)"
case "$dry" in
  *"Aura-Glass-Moga-Cyan"*"Moga-Neon-Cyan.zip"*) ;;
  *) fail "teal moga dry run did not select official Cyan" ;;
esac

accent_only="$(bash "$ROOT/install.sh" --settings-only --dry-run \
      --accent pink -y 2>&1)"
case "$accent_only" in
  *"Moga cursor refresh"*) ;;
  *) fail "remembered moga did not schedule an accent-only refresh" ;;
esac
```

Run the second case with a temporary `AURA_GLASS_CONF` containing
`cursor-pack=moga`; it must not call the network in dry-run mode. Assert the
source files contain `moga` in CLI validation and the gsettings branch.

- [ ] **Step 2: Run the lifecycle checker to verify RED**

Run: `bash tools/check-moga-cursors.sh`

Expected: FAIL because the installer has no Moga fetch/install/selection path.

- [ ] **Step 3: Implement safe download, installation, and selection**

1. Refactor `fetch_zip_pinned` through a shared internal ZIP downloader, then
   add `fetch_zip_md5_pinned URL MD5 DEST`. It must mirror the existing ZIP
   extraction rules (`__MACOSX` and `.DS_Store` excluded, destination rebuilt
   only after a checksum match) but calculate `md5sum`; its comment must state
   Moga's official metadata publishes MD5 rather than SHA-256.
2. Add `MOGA_PAGE_URL="https://www.gnome-look.org/p/2302110"` in
   `lib/steps.sh` beside the cursor source constants.
3. In `lib/steps-assets.sh`, add `moga_cursor_theme`, `moga_variant`, and
   `install_moga_cursors`. In a real run, curl
   `"$MOGA_PAGE_URL/loadFiles"` into a `mktemp` metadata file, pass it to
   `tools/moga_cursor.py resolve "$ACCENT"`, and call `fetch_zip_md5_pinned`
   with the returned URL and MD5. In a dry run, call only `variant` and print
   the selected archive/destination; do not fetch metadata.
4. From the extracted cache, require exactly one `index.theme` with a sibling
   `cursors/` directory, copy that theme into a temporary directory, update
   only its `Name=` to `Aura Glass Moga Neon <Variant>`, then use `run` to
   replace only `$HOME/.local/share/icons/Aura-Glass-Moga-<Variant>`.
5. Add `moga` to `install.sh` usage, validation, summary, and terminal pointer
   question. Keep AOSP as the default; insert Moga as option 4 and move
   Default to option 5.
6. In the `--settings-only` assets branch, call `install_cursors` when a cursor
   was explicitly selected **or** the resolved pack is `moga` and the accent
   was explicit. In `apply_gsettings`, choose `moga_cursor_theme "$ACCENT"`
   only after `install_moga_cursors` has made its directory available.

- [ ] **Step 4: Run focused checks to verify GREEN**

Run:

```bash
bash tools/check-moga-cursors.sh
bash install.sh --settings-only --dry-run --cursors moga --accent teal -y
```

Expected: all fixture checks pass, and the dry run names
`Moga-Neon-Cyan.zip` plus `Aura-Glass-Moga-Cyan` without downloading anything.

- [ ] **Step 5: Commit the installer lifecycle**

```bash
git add lib/common.sh lib/steps.sh lib/steps-assets.sh lib/steps-dconf.sh \
  install.sh tools/check-moga-cursors.sh
git commit -m "feat(assets): install Moga cursors by accent"
```

### Task 3: Settings window and setup wizard parity

**Files:**
- Modify: `gui/aura_glass_settings.py:431-438,637,2172-2185,3574-3601`
- Modify: `gui/aura_glass_setup_wizard.py:101-118,695-710`
- Modify: `tools/check-gui-flags.py:395-400`
- Modify: `tools/check-wizard-flags.py:1-180`

**Interfaces:**
- Consumes: installer flag `--cursors moga` from Task 2.
- Produces: settings-window accent changes retain `--cursors moga` when Moga
  remains selected.
- Produces: wizard Moga selection with the official Moyash product-page link.

- [ ] **Step 1: Write failing GUI/wizard checker cases**

Add these `tools/check-gui-flags.py` transitions:

```python
("moga pointer", FROSTED, state(cursors="moga"),
 ["--cursors", "moga"]),
("moga follows an accent change", state(cursors="moga", accent="purple"),
 state(cursors="moga", accent="teal"),
 ["--accent", "teal", "--cursors", "moga"]),
```

Add a `tools/check-wizard-flags.py` case whose answer is
`answers(cursors="moga")` and whose expected argv substitutes
`["--cursors", "moga", "--cursor-size", "20", "--osd"]` into `PACKS`.
Assert `PACK_LINKS["moga"] == "https://www.gnome-look.org/p/2302110"`.

- [ ] **Step 2: Run GUI/wizard checks to verify RED**

Run:

```bash
python3 tools/check-gui-flags.py
python3 tools/check-wizard-flags.py
```

Expected: FAIL because neither UI recognizes `moga` or repeats it with an
accent change.

- [ ] **Step 3: Implement UI parity without copying the colour map**

1. Add `("moga", "Moga Neon", "Official Moga Neon cursor — follows Accent color. By Moyash")`
   to `CURSOR_PACKS`; do not add nine color rows.
2. In `Settings.flags_against`, after emitting a changed accent, append
   `--cursors moga` when both the new and previous settings choose `moga`.
   The installer, not the window, still resolves teal to Cyan.
3. Add `Aura-Glass-Moga-` to `ICON_PACK_FAMILIES`, so the window inventories
   only generated Aura Glass variants and never a user-installed Moga folder.
4. Add `moga` to `PACK_LINKS`, `PACK_NAMES`, and the cursor radio rows. Its
   subtitle must say it follows Aura Glass's accent and credit Moyash. Rename
   the generic button label in `radio_rows` from `View on GitHub` to
   `View source`, because Moga's verified source is GNOME-Look.

- [ ] **Step 4: Run GUI/wizard checks to verify GREEN**

Run:

```bash
python3 tools/check-gui-flags.py
python3 tools/check-wizard-flags.py
```

Expected: every composition and dry-run acceptance case passes, including the
atomic teal-plus-Moga argv.

- [ ] **Step 5: Commit GUI and wizard parity**

```bash
git add gui/aura_glass_settings.py gui/aura_glass_setup_wizard.py \
  tools/check-gui-flags.py tools/check-wizard-flags.py
git commit -m "feat(gui): offer accent-following Moga cursors"
```

### Task 4: Lifecycle documentation and attribution

**Files:**
- Modify: `uninstall.sh:312-317`
- Modify: `README.md:129-136,301-304,328-334`
- Modify: `docs/CONFIG-REFERENCE.md:79-86,165-170`
- Modify: `docs/ARCHITECTURE.md:359-365`
- Modify: `tools/check-moga-cursors.sh`

**Interfaces:**
- Consumes: generated prefix `Aura-Glass-Moga-` from Task 2.
- Produces: `uninstall.sh --assets` removes only Aura Glass-generated Moga
  directories, while docs name the official upstream and the behavior.

- [ ] **Step 1: Add failing lifecycle/documentation assertions**

Extend `tools/check-moga-cursors.sh` to require:

```bash
rg -q 'Aura-Glass-Moga-' "$ROOT/uninstall.sh"
rg -q 'Moyash' "$ROOT/README.md"
rg -q 'https://www.pling.com/u/moyash' "$ROOT/README.md"
rg -q 'moga' "$ROOT/docs/CONFIG-REFERENCE.md"
```

Also reject an uninstall glob that begins `Moga-`, because it could delete the
user's standalone upstream theme.

- [ ] **Step 2: Run the lifecycle/documentation assertion to verify RED**

Run: `bash tools/check-moga-cursors.sh`

Expected: FAIL because neither uninstaller nor documentation identifies the
generated Moga family and Moyash credit is absent.

- [ ] **Step 3: Implement lifecycle boundaries and docs**

1. Add only `"$HOME"/.local/share/icons/Aura-Glass-Moga-*` to the assets
   removal loop. Leave `Moga-Neon-*` and any cache outside that generated
   prefix untouched.
2. Expand the README `--cursors` option with `moga` and explain that it follows
   Aura Glass Accent by selecting official variants, not a custom color picker.
3. Add a Moga Cursors row naming **Moyash** and a `[moga]` reference to
   `https://www.pling.com/u/moyash`; retain existing third-party credits.
4. Update the configuration reference memo enum and gsettings text to include
   `moga`, and the architecture `apply_gsettings` description to state that it
   selects the accent-resolved Moga directory.

- [ ] **Step 4: Run the lifecycle/documentation assertion to verify GREEN**

Run: `bash tools/check-moga-cursors.sh`

Expected: the checker proves credit, documentation, and the narrow uninstall
ownership boundary.

- [ ] **Step 5: Commit lifecycle docs**

```bash
git add uninstall.sh README.md docs/CONFIG-REFERENCE.md docs/ARCHITECTURE.md \
  tools/check-moga-cursors.sh
git commit -m "docs: credit Moyash for Moga cursors"
```

### Task 5: Full regression gate and live desktop proof

**Files:**
- Verify: all Task 1-4 files

**Interfaces:**
- Consumes: completed installer and UI implementation.
- Produces: evidence that the selected Moga theme changes with Aura Glass
  accent while cursor-size remains untouched.

- [ ] **Step 1: Run the complete repository gate**

Run:

```bash
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath \
GIT_CONFIG_VALUE_0=/dev/null bash tools/hooks/pre-commit
```

Expected: exit 0. The temporary-repository update-check fixture inherits the
host hook path, so the explicit `/dev/null` override prevents recursive hooks
inside that fixture while the command still runs the complete staged-tree gate.

- [ ] **Step 2: Apply Purple Moga on the live desktop**

Record the current size, then run the supported installer path:

```bash
before_size="$(gsettings get org.gnome.desktop.interface cursor-size)"
./install.sh --settings-only --cursors moga --accent purple -y
gsettings get org.gnome.desktop.interface cursor-theme
gsettings get org.gnome.desktop.interface cursor-size
test -r "$HOME/.local/share/icons/Aura-Glass-Moga-Purple/index.theme"
test -d "$HOME/.local/share/icons/Aura-Glass-Moga-Purple/cursors"
```

Expected: `cursor-theme` is `'Aura-Glass-Moga-Purple'`, the theme has an
`index.theme` and cursor directory, and `cursor-size` equals `before_size`.

- [ ] **Step 3: Prove accent-only switching**

Run:

```bash
./install.sh --settings-only --accent teal -y
gsettings get org.gnome.desktop.interface cursor-theme
gsettings get org.gnome.desktop.interface cursor-size
test -r "$HOME/.local/share/icons/Aura-Glass-Moga-Cyan/index.theme"
```

Expected: `cursor-theme` is `'Aura-Glass-Moga-Cyan'`, proving the remembered
Moga choice followed the new accent; cursor-size remains equal to `before_size`.

- [ ] **Step 4: Inspect the final committed history and working tree**

Run:

```bash
git -c core.bare=false --git-dir=.git --work-tree=. log --oneline -4
git -c core.bare=false --git-dir=.git --work-tree=. show --check --stat HEAD
git -c core.bare=false --git-dir=.git --work-tree=. status --short
```

Expected: the newest commits are the four Moga tasks, `git show --check` has
no whitespace errors, and only the known pre-existing unrelated changes remain
outside the Moga commits. Do not create an empty final commit.
