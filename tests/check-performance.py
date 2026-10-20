#!/usr/bin/env python3
"""Session-free regressions for package placeholder rows."""
import ast
from pathlib import Path
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PerformanceTests(unittest.TestCase):
    def test_empty_system_pack_group_is_not_queried_for_an_owner(self):
        tree = ast.parse((ROOT / 'gui/aura_glass_settings.py').read_text())
        method = next(node for node in ast.walk(tree)
                      if isinstance(node, ast.FunctionDef) and node.name == '_own_next_pack')
        namespace = {}
        exec(compile(ast.Module(body=[method], type_ignores=[]), str(ROOT / 'gui/aura_glass_settings.py'), 'exec'), namespace)
        group = object()
        window = SimpleNamespace(_packs_system=group, _pack_rows=[(group, SimpleNamespace())])
        self.assertFalse(namespace['_own_next_pack'](window))

if __name__ == '__main__':
    unittest.main()
