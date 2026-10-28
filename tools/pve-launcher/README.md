# BAR PVE launcher

This is the source for the existing Windows Forms launcher in `D:\BeyondAllReason\BAR-Server\friend-launcher`. It uses the installed BAR client and stock RecoilEngine.

Build with Windows PowerShell:

```powershell
.\Build.ps1 -OutputDirectory D:\BeyondAllReason\BAR-Server\friend-launcher
```

Build.ps1 compiles `Program.cs` and copies the launcher scripts and the versioned game updater from `../pve-distribution`. Keep `server.json` outside Git and set `pve_status_source` to the local server's `pve-data\server-version.json`. A future public client may set this to an HTTPS status endpoint. Use `server.example.json` as the schema.

Modes:

- Official: restores the original BAR lobby configuration and starts the installed official client.
- PVE: checks server readiness and its pinned GitHub Release manifest, installs the exact package, verifies its size, SHA-256 and `modinfo.lua`, and then connects to the private lobby.
- Development: starts the local BAR-PVE Git tree in an isolated single-player Recoil session.

The PVE store is `data\bar-pve`. Its `state.json` keeps active and historical versions. Installed archives are linked or copied into `data\games` under their PVE-only names. The updater blocks activation and rollback while Recoil is running. Engine updates are deliberately separate from game updates.
