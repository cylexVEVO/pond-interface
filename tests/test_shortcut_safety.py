import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "shortcuts", Path(__file__).resolve().parents[1] / "shell/settings/shortcuts/shortcuts.py")
shortcuts = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shortcuts)


class ShortcutSafetyTests(unittest.TestCase):
    def test_typing_and_navigation_require_modifier(self):
        for key in ("Space", "a", "1", "Slash", "Return", "Tab", "BackSpace",
                    "Delete", "Escape", "Left", "Home", "KP_Enter", "eacute"):
            for prefix in ("", "Shift+"):
                with self.subTest(chord=prefix + key):
                    self.assertTrue(shortcuts.safety_error(prefix + key))

    def test_modified_and_dedicated_keys_allowed(self):
        for chord in ("Mod+Space", "ctrl+shift+a", "Alt+Tab", "Super+Return",
                      "F1", "F35", "Shift+F5", "XF86AudioMute",
                      "XF86MonBrightnessUp", "Print"):
            with self.subTest(chord=chord):
                self.assertEqual(shortcuts.safety_error(chord), "")

    def test_rejected_save_and_rebind_preserve_files(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "keys.kdl"
            meta = Path(directory) / "shortcuts.json"
            config.write_text('binds {\n    Mod+A { spawn "test"; }\n}\n')
            meta.write_text('[]\n')
            original = (config.read_bytes(), meta.read_bytes())
            with patch.multiple(shortcuts, USER_CONFIG=config, USER_KEYBINDS=config, META=meta):
                changes = [
                    lambda: shortcuts.save("Mod+A", {"key": "Space", "action": 'spawn "test";'}),
                    lambda: shortcuts.rebind("Mod+A", "Shift+Space"),
                ]
                for change in changes:
                    with self.assertRaisesRegex(ValueError, "Hold Super"):
                        shortcuts.transaction(change)
                    self.assertEqual((config.read_bytes(), meta.read_bytes()), original)


if __name__ == "__main__":
    unittest.main()
