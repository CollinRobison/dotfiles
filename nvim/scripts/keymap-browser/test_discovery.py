"""Exercise Atlas and the Keymaps catalog against the same temporary Lua sources."""
import shutil
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch

import catalog
import smart_search


@unittest.skipUnless(shutil.which(catalog.nvim_bin()), "Neovim is required for source discovery")
class DiscoveryTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.config = Path(directory.name).resolve()
        self.atlas = catalog.guide()
        settings = patch.multiple(self.atlas, NVIM=self.config, LUA=self.config / "lua",
                                  CATEGORY_FILE=self.config / "categories.json")
        settings.start()
        self.addCleanup(settings.stop)
        self.write_lua("init.lua", """
            vim.g.mapleader = ' '
            require('collin.ai')
            require('collin.remap')
        """)
        self.write_lua("lua/collin/ai/init.lua", """
            vim.keymap.set({'n', 'x'}, '<leader>q9', '<cmd>OrchidStamp<CR>', { desc = 'Mark this spot' })
            vim.keymap.set('i', '<F17>', function() end, { desc = 'Splice a test fragment' })
            vim.api.nvim_create_user_command('OrchidStamp', function()
              local callback_notes = { desc = 'Not the command description' }
            end, {
              desc = 'Pin the temporary orchid',
            })
            -- vim.api.nvim_create_user_command('GhostStamp', function() end, {})
        """)
        self.write_lua("lua/collin/lazy/codecompanion.lua", """
            return { 'placeholder/example', keys = {
              { 'gZ', function() end, mode = 'v', desc = 'Rotate the fixture' },
              { '<F18>', function() end, desc = 'Open the fixture' },
            } }
        """)
        self.write_lua("lua/collin/remap.lua", """
            vim.keymap.set('n', 'gF', '<cmd>OrdinaryNotice<CR>', { desc = 'AI assisted words alone' })
            vim.api.nvim_create_user_command('OrdinaryNotice', function() end, { desc = 'Show a notice' })
            vim.keymap.set('n', 'gL', '<cmd>Lazy<CR>', { desc = 'Open plugins' })
        """)

    def write_lua(self, name, source):
        path = self.config / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")

    def atlas_inventory(self, payload):
        entries = self.atlas.apply_saved_categories(self.atlas.extract_mappings(payload), interactive=False)
        commands = self.atlas.extract_commands(payload)
        modes = {(row.key, row.mode) for row in entries if row.category == "AI assisted"}
        self.assertEqual(modes, {("Space q9", "Normal"), ("Space q9", "Visual"), ("<F17>", "Insert"),
                                 ("gZ", "Visual"), ("gZ", "Select"), ("<F18>", "Normal")})
        orchid, = [item for item in commands if item.name == "OrchidStamp"]
        self.assertEqual((orchid.description, orchid.category, orchid.source),
                         ("Pin the temporary orchid", "AI assisted", "lua/collin/ai/init.lua"))
        normal, = [item for item in commands if item.name == "OrdinaryNotice"]
        self.assertEqual((normal.category, normal.description), ("Personal Controls", "Show a notice"))
        self.assertTrue(any(item.name == "Lazy" for item in commands))
        self.assertFalse(any(item.name == "GhostStamp" for item in commands))
        return entries, commands

    def test_atlas_sections_and_descriptions(self):
        payload = self.atlas.load_source_payload()
        self.assertIsNotNone(payload)
        entries, commands = self.atlas_inventory(payload)
        document = self.atlas.build_html(entries, self.atlas.extract_tools(), commands,
                                         self.atlas.extract_functions(), 0, "Runtime audit skipped")
        self.assertIn("AI assisted · Ex commands", document)
        self.assertIn("<h1 class=''>AI assisted</h1>", document)
        self.assertIn("<td>Insert</td><td><kbd>&lt;F17&gt;</kbd></td><td>Splice a test fragment</td>", document)
        self.assertIn("<code>:OrchidStamp</code></td><td>Pin the temporary orchid</td>", document)
        self.assertEqual(document.count("<code>:OrchidStamp</code>"), 1)
        self.assertNotIn("GhostStamp", document)

    def test_atlas_legacy_fallback(self):
        self.atlas_inventory(None)

    @patch.object(catalog, "external_shortcuts", return_value=([], []))
    def test_browser_catalog_modes_sources_and_read_only_commands(self, _):
        inventory = catalog.Catalog(self.config)
        self.assertIsNone(inventory.runtime_warning)
        mappings = [row for row in inventory.rows if row["group"] == "AI assisted" and row["editable"]]
        self.assertEqual({row["key"]: row["modes"] for row in mappings},
                         {"<leader>q9": ["n", "x"], "<F17>": ["i"], "gZ": ["x", "s"], "<F18>": ["n"]})
        self.assertFalse(any(row["origin"] == "Runtime" and row["desc"] == "Mark this spot"
                             for row in inventory.rows))
        command, = [row for row in inventory.rows if row["key"] == ":OrchidStamp"]
        self.assertEqual(catalog.public_row(command), {
            "id": "command:OrchidStamp", "kind": "command", "key": ":OrchidStamp", "context": "Ex command",
            "scope": "", "group": "AI assisted", "file": "lua/collin/ai/init.lua", "line": 3,
            "desc": "Pin the temporary orchid", "modes": [], "origin": "Config", "editable": False,
        })
        self.assertEqual(command["chords"], ())
        self.assertIsNone(smart_search.build_step({"mode": "n", "bindings": [1]}, {1: command}, [], {}))
        leader_mapping = next(row for row in mappings if row["key"] == "<leader>q9")
        self.assertFalse(any(issue["key"] == command["key"] for issue in inventory.propose(leader_mapping, command["key"])))
        with patch.object(smart_search, "run_pi", return_value={"matches": [1], "solutions": []}) as pi:
            result = smart_search.smart_search({"query": "Pin the orchid"}, [command], " ", "\\", {})
        self.assertEqual(pi.call_args.args[0]["prompt"]["bindings"][0][-1], "command")
        self.assertEqual(result["rows"][0]["key"], ":OrchidStamp")
        self.assertFalse(any(row["key"] == ":GhostStamp" for row in inventory.rows))
        self.assertTrue(any(row["origin"] == "Built-in" and row["key"] == "dd" for row in inventory.rows))
        self.assertTrue(any(row["editable"] and row["key"] == "gF" and row["group"] == "Personal Controls"
                            for row in inventory.rows))
        self.assertTrue(any(row["key"] == ":OrdinaryNotice" and row["group"] == "Personal Controls"
                            for row in inventory.rows))


if __name__ == "__main__":
    unittest.main()
