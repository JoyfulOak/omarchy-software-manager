import unittest

from helpers.software_manager import (
    build_flatpak_update_command,
    build_flatpak_update_commands,
    build_uninstall_command,
    parse_flatpak_inventory,
    parse_pacman_inventory,
    parse_updates,
)


class InventoryTests(unittest.TestCase):
    def test_pacman_inventory_marks_foreign_packages_as_aur(self):
        rows = parse_pacman_inventory(
            "firefox 135.0-1\nmy-tool 2.1-3\n",
            "my-tool 2.1-3\n",
        )
        self.assertEqual(
            rows,
            [
                {
                    "id": "firefox",
                    "name": "firefox",
                    "version": "135.0-1",
                    "type": "Arch",
                    "source": "Official repositories",
                    "location": "System",
                },
                {
                    "id": "my-tool",
                    "name": "my-tool",
                    "version": "2.1-3",
                    "type": "AUR / foreign",
                    "source": "Foreign package",
                    "location": "System",
                },
            ],
        )

    def test_flatpak_inventory_keeps_installation_and_origin(self):
        rows = parse_flatpak_inventory(
            "org.example.Editor\tEditor\t1.4\tflathub\tuser\n",
            default_scope="user",
        )
        self.assertEqual(rows[0]["id"], "org.example.Editor")
        self.assertEqual(rows[0]["type"], "Flatpak")
        self.assertEqual(rows[0]["source"], "flathub")
        self.assertEqual(rows[0]["location"], "User installation")

    def test_uninstall_uses_safe_provider_specific_commands(self):
        self.assertEqual(
            build_uninstall_command({"type": "Arch", "id": "firefox"}),
            ["pkexec", "pacman", "-R", "--noconfirm", "--", "firefox"],
        )
        self.assertEqual(
            build_uninstall_command(
                {"type": "Flatpak", "id": "org.example.Editor", "location": "User installation"}
            ),
            ["flatpak", "uninstall", "--user", "--noninteractive", "--", "org.example.Editor"],
        )

    def test_uninstall_rejects_invalid_or_unknown_package(self):
        with self.assertRaises(ValueError):
            build_uninstall_command({"type": "Arch", "id": "firefox; rm -rf /"})
        with self.assertRaises(ValueError):
            build_uninstall_command({"type": "Unknown", "id": "anything"})


class UpdateTests(unittest.TestCase):
    def test_update_output_uses_package_and_version_separator(self):
        self.assertEqual(
            parse_updates("firefox 135.0-1 -> 136.0-1\n", "Arch"),
            [{"id": "firefox", "type": "Arch", "current": "135.0-1", "available": "136.0-1"}],
        )

    def test_flatpak_update_command_is_limited_to_selected_scope_and_id(self):
        self.assertEqual(
            build_flatpak_update_command("User installation", "org.example.Editor"),
            ["flatpak", "update", "--user", "--noninteractive", "--", "org.example.Editor"],
        )
        self.assertEqual(
            build_flatpak_update_command("System installation", "all"),
            ["pkexec", "flatpak", "update", "--system", "--noninteractive"],
        )

    def test_all_flatpak_updates_cover_user_and_system_installations(self):
        self.assertEqual(
            build_flatpak_update_commands("All installations", "all"),
            [
                ["pkexec", "flatpak", "update", "--system", "--noninteractive"],
                ["flatpak", "update", "--user", "--noninteractive"],
            ],
        )

    def test_flatpak_update_rejects_untrusted_id_and_location(self):
        with self.assertRaises(ValueError):
            build_flatpak_update_command("User installation", "org.app; malicious")
        with self.assertRaises(ValueError):
            build_flatpak_update_command("Unknown", "all")


if __name__ == "__main__":
    unittest.main()
