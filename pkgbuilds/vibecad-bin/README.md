# VibeCAD on Omarchy

Launch VibeCAD from the application menu or run `vibecad`. The launcher reads the focused Hyprland monitor's scale because the upstream AppImage forces Qt's XCB backend. Fonts and icons retain their upstream defaults and scale together. No font preferences, theme files, window modes, or global display settings are changed by the package.

Scaling is selected at startup. Restart VibeCAD after moving to a differently scaled monitor. Explicit Qt scaling environment variables take precedence. Outside a reachable Hyprland session, the launcher leaves Qt's scaling unchanged.

Updates are managed by pacman; the supported VibeCAD update policy disables its in-app updater. On AMD hardware the launcher also preloads the host's `libdrm_amdgpu` to avoid a conflict with the bundled library.

For installations that used the earlier Isengard experiments, user launchers and desktop overrides can shadow the packaged launcher. Retire those overrides after installing this package revision. The package deliberately does not modify files in users' home directories.
