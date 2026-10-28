# BAR PVE launcher

This is the source for the existing Windows Forms launcher in `D:\BeyondAllReason\BAR-Server\friend-launcher`. It uses the installed BAR client and stock RecoilEngine.

Build with Windows PowerShell:

```powershell
.\Build.ps1 -OutputDirectory D:\BeyondAllReason\BAR-Server\friend-launcher
```

Build.ps1 compiles `Program.cs` and copies the launcher scripts and the versioned game updater from `../pve-distribution`. Keep the local `server.json` outside Git. For a friend build, `Package-BarPveFriendLauncher.ps1` creates a distributable zip using `server.friend.example.json`.

Modes:

- Official: restores the original BAR lobby configuration and starts the installed official client.
- PVE: checks server readiness and its pinned GitHub Release manifest, installs the exact package, verifies its size, SHA-256 and `modinfo.lua`, and then connects to the private lobby.
- Development: starts the local BAR-PVE Git tree in an isolated single-player Recoil session.

The PVE store is `data\bar-pve`. Its `state.json` keeps active and historical versions. Installed archives are linked or copied into `data\games` under their PVE-only names. The updater blocks activation and rollback while Recoil is running. Engine updates are deliberately separate from game updates.

For the local PVE room, stop SPADS and run `..\pve-distribution\Sync-BarPveServerPreset.ps1 -ServerRoot D:\BeyondAllReason\BAR-Server -ActivateDefault`, then start SPADS. This verifies the server archive and changes only its default hosting preset to `pve`, with a config backup. The launcher refuses PVE multiplayer until it sees the matching preset and live SPADS process.

The local server writes `pve-data\server-version.json`. To publish that file for friends, run `Sync-BarPveServerPreset.ps1 -ServerRoot D:\BeyondAllReason\BAR-Server -PublishStatus -GitRepository D:\BeyondAllReason\BAR-PVE`. It commits only `status/server-version.json` to `pve/main` and pushes it. The public read-only address is `https://raw.githubusercontent.com/GodAlone945/Beyond-All-Reason/pve/main/status/server-version.json`. The PVE repo must be clean in its index and synchronized with `origin/pve/main`; Git Credential Manager must be signed in.

Build a friend package with `Package-BarPveFriendLauncher.ps1 -PackageDirectory D:\BAR-PVE-Friend-Build -OutputDirectory D:\BAR-PVE-Releases`. The package config uses the public GitHub status URL and configured lobby endpoint; it contains no local server paths.
