# CLAUDE.md

Pi Tunnel: a macOS 13+ menu bar app (plain Swift + AppKit, no dependencies)
that shows the state of an SSH port-forwarding tunnel, one brick per port.
Public repo under the ByteApps org; site at byteapps.com/pi-tunnel from `docs/`.

## Layout

- `Sources/` — `main.swift` boots an accessory app; `AppDelegate.swift` owns the
  status item, menu, polling and actions; `TunnelIcon.swift` draws the template
  icon; `PortProbe.swift` decides open/busy/down (TCP connect + `lsof` owner);
  `TunnelController.swift` runs `ssh -f -N` / SIGTERM; `Config.swift` loads and
  saves `~/.config/pi-tunnel/ports.json`; `PortsEditor.swift` is the Edit Ports
  window. `--edit-ports` as a launch argument opens that window at start.
- `build.sh` — universal build, optional Developer ID signing + notarization,
  `--install` / `--release`. `Info.plist` holds the version.
- `docs/` — landing page and the images the README also uses.

## Build and release

- Build with `./build.sh`. It calls the Xcode toolchain's `swiftc` directly
  with an explicit `-sdk`; plain `swiftc`/`xcrun` cannot write their cache
  inside a sandboxed shell.
- Releases must be signed and notarized:
  `SIGN_IDENTITY="Developer ID Application: ByteApps LLC (ASM36PB3X5)" NOTARY_PROFILE=byteapps ./build.sh --release`.
  The identity and notarytool profile live in the maintainer's login keychain.
- Never run `build.sh` while a notarization is in flight: it wipes `build/`,
  and the stapling step at the end expects the app that was submitted.
- Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`,
  commit, tag `vX.Y.Z`, then `gh release create` with `build/Pi-Tunnel-X.Y.Z.zip`.
- Every commit and tag is GPG-signed; GitHub must show them as verified.

## Rules

- Nothing personal in this repo: no real hostnames, usernames, home paths,
  addresses or port lists from the maintainer's own setup. Defaults in
  `Config.swift` and the README examples stay generic (`pi@raspberrypi.local`).
- Keep the README's Configure section about the Edit Ports window; the JSON
  file is mentioned as the thing behind it, not documented as the interface.
- The menu's last section is `More from ByteApps…` then `Quit`; keep the
  marketing row to one line so the menu width stays set by the port rows.
