# Software for Omarchy

**Software** is an Omarchy shell bar plugin for managing installed applications in a large pop-out window. Its layout and bar-to-panel handoff follow the installed Omarchy Plugin Manager, with an app/package inventory in place of the plugin catalog.

## Features

- One searchable installed-software list with filters for **Arch**, **AUR / foreign**, and **Flatpak**.
- Shows package version, source/remote, and installation location (system or Flatpak user/system).
- Checks Arch repository updates with `checkupdates`, foreign/AUR updates with `yay`, and Flatpak app updates in both installation scopes.
- Native Arch/AUR updates open `yay -Syu` in the configured terminal. Arch requires full system upgrades rather than partial per-package upgrades; the terminal lets you review the transaction before approving it.
- Flatpak updates can target one app or all Flatpak installations. System-scope actions may request authorization.
- Uninstall requires an in-app confirmation. Native removals remove only the selected package; Flatpak removals do not pass `--delete-data`.
- Dynamic package and remote text is rendered as plain text, and process actions use argument arrays rather than a shell.

## Inventory coverage

The inventory includes explicitly installed Arch packages (including foreign/AUR packages) and Flatpak **apps** installed for the user or system. Flatpak runtimes are not shown as apps. Dependency-only Arch packages and software installed outside these package managers (for example, AppImages or manually installed binaries) are not currently inventoried.

## Install locally

From this repository, copy the plugin into Omarchy's user plugin directory, then enable it:

```sh
PLUGIN="$HOME/.config/omarchy/plugins/io.github.joyfuloak.omarchy-software-manager"
mkdir -p "$PLUGIN/helpers"
cp manifest.json BarWidget.qml Expanded.qml "$PLUGIN/"
cp helpers/software_manager.py "$PLUGIN/helpers/"
omarchy plugin validate "$PLUGIN"
omarchy plugin enable io.github.joyfuloak.omarchy-software-manager
```

The widget uses the package icon in the bar. Click it to open the compact card, then **Open Software Manager** for the large window. The plugin remains separate from the Plugin Manager; the reference plugin is not modified.

## Tests

```sh
python -m unittest discover -s tests -v
omarchy plugin validate .
```

The tests cover inventory parsing, provider/scope reporting, safe command construction, and update command selection. They do not execute package-manager mutations.

## Notes

- Update checks read package-manager metadata and do not install updates.
- Uninstalling a package can affect other packages that depend on it; the native transaction removes only the named package and does not cascade-remove dependencies.
- This first version does not install new software. It inventories, updates, and removes supported packages.
