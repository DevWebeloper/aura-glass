# Pull Request: Fix GNOME 50/51 Compatibility (Shell.GLSLEffect removal)

**Target Repository**: `boerdereinar/copyous`  
**Branch**: `main`  
**Patch File**: [`patches/copyous-gnome51.patch`](../../patches/copyous-gnome51.patch)

---

## Summary

In GNOME Shell 50 and 51, `Shell.GLSLEffect` was removed from GObject introspection in favor of Mutter Clutter effects. When running Copyous under GNOME 50/51, importing `lib/ui/items/clipboardItem.js` throws an unhandled error during extension loading:

```text
TypeError: class heritage (intermediate value).GLSLEffect is not an object or null
```

This prevents the extension from enabling and causes GNOME Shell to flag it as errored.

## Solution

1. Provide a backward-compatible fallback for `BaseEffect`:
   ```javascript
   const BaseEffect = Shell.GLSLEffect || Clutter.Effect;
   let HoleEffect = class HoleEffect extends BaseEffect { ... }
   ```
2. Guard calls to `GLSLEffect`-specific uniform inspection (`_sizeLocation`, `_holeBoxLocation`) and pipeline hooks (`vfunc_build_pipeline`, `vfunc_paint_target`) when `Shell.GLSLEffect` is not available.
3. Add `"50"` and `"51"` to `shell-version` in `metadata.json`.

## Verification & Testing

- Verified on GNOME Shell 51.0 (Wayland).
- The extension loads without errors, connects to the clipboard manager, and displays preview cards seamlessly.
- Backward compatibility preserved for GNOME 45-48.
