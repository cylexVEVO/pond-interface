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

    def test_inline_removal_preserves_block_and_neighbor(self):
        text = 'binds { Mod+A { quit; }; Mod+B { quit; }; }'
        result, found = shortcuts.drop_line(text, "Mod+A")
        self.assertTrue(found)
        self.assertIn('binds {', result)
        self.assertIn('Mod+B { quit; }', result)
        self.assertTrue(result.endswith('}'))

    def test_invalid_chord_structure(self):
        for key in ("Mod", "Mod+", "Mod++A", 'Mod+A { quit; }'):
            self.assertEqual(shortcuts.canonical(key), "")

    def test_validation_failure_never_writes_live_files(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "keys.kdl"
            meta = Path(directory) / "shortcuts.json"
            original = 'binds {\n    Mod+A { quit; }\n}\n'
            config.write_text(original)
            meta.write_text("[]")
            with patch.multiple(shortcuts, USER_CONFIG=config, USER_KEYBINDS=config, META=meta):
                with patch.object(shortcuts, "validate", side_effect=ValueError("rejected")):
                    with patch.object(shortcuts.kdl, "atomic_write") as write:
                        with self.assertRaisesRegex(ValueError, "rejected"):
                            shortcuts.transaction(lambda: shortcuts.save(
                                "Mod+A", {"key": "Mod+B", "action": "unknown-action;"}))
                        write.assert_not_called()
            self.assertEqual(config.read_text(), original)
            self.assertEqual(meta.read_text(), "[]")

    def test_success_publishes_only_final_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "keys.kdl"
            meta = Path(directory) / "shortcuts.json"
            config.write_text('binds {\n    Mod+A { quit; }\n}\n')
            with patch.multiple(shortcuts, USER_CONFIG=config, USER_KEYBINDS=config, META=meta):
                with patch.object(shortcuts, "validate") as validate:
                    shortcuts.transaction(lambda: shortcuts.save(
                        "Mod+A", {"key": "Mod+B", "action": "quit;"}))
                    validate.assert_called_once()
                    self.assertEqual(validate.call_args.args[0], config.read_text())
            self.assertNotIn("Mod+A", config.read_text())
            self.assertIn("Mod+B", config.read_text())


if __name__ == "__main__":
    unittest.main()
