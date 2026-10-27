# BAR PVE distribution architecture

## Observed local state (2026-10-27)

- Development source: D:\BeyondAllReason\Beyond-All-Reason\data\games\BAR.sdd. It contains uncommitted live-interaction changes and is not the SPADS game archive.
- Server: D:\BeyondAllReason\BAR-Server. SPADS uses spads\etc\spads.conf, springDataDir=D:\BeyondAllReason\BAR-Server\spads\var\spring\data and an auto-managed Recoil engine. Its hosting preset currently matches the official test game by regular expression. The latest startscript names Beyond All Reason test-31691-a617033.
- Server game bytes reside in spring\data\packages as Rapid .sdp plus pool chunks, rather than in games\BAR.sdd. The client log also names that official test game.
- Friend launcher: C# WinForms Program.cs and PowerShell scripts. It currently switches Chobby lobby configuration and starts the stock Electron launcher. It has no game-channel selector or package updater. The stock launcher downloads official resources.
- BarAutoUpdate plugin is configured but not loaded by SPADS; the local README says it was disabled after blocking the lobby event loop.

## Source and update boundaries

This worktree is the PVE source on branch pve/main, forked from the committed BAR master. The official upstream remote is named upstream; origin remains the user's fork. Merge upstream/master into pve/main only in this worktree, review conflicts, then build a new PVE release. The original BAR.sdd and its working changes stay separate.

The independent modinfo identity is BAR PVE 0.1.0-dev.1. Every release changes version before packaging. Avoid a directory or archive with the same game identity as official BAR. Never place the PVE release into the official launcher's managed Rapid store. Do not assume a file name alone selects a game; verify unitsync's game list and the generated startscript.

## Intended directory layout

- Source: D:\BeyondAllReason\BAR-PVE (Git worktree)
- Server PVE packages: D:\BeyondAllReason\BAR-Server\pve-data\games\BAR-PVE-<version>.sdz
- Client PVE data: <launcher data>\bar-pve\games\BAR-PVE-<version>.sdz
- Client update state: <launcher data>\bar-pve\state.json
- Client staging: <launcher data>\bar-pve\staging\<version>
- Client engine: stock RecoilEngine path for phase one; reserve an engine object in the manifest for a later independent update.

The PVE data root must be a separate engine isolation directory that can still see required engine base assets and maps. A game session pins a concrete version and package path. Update checks may continue while in game; activation waits until all PVE engine processes have exited. No active .sdz is replaced or removed. Keep at least one previous verified package for rollback.

## Release contract

Publish a GitHub Release with immutable BAR-PVE-<version>.sdz and manifest.json. The manifest is served over HTTPS and contains schemaVersion=1, channel=pve, version, gameName, package URL, SHA-256 and size, plus the required engine version. The publisher must verify the built archive's modinfo name/version with unitsync, calculate SHA-256 and size from final bytes, then upload both files. Do not retag or replace assets under a published version. A channel pointer may select the latest immutable manifest; it must itself be authenticated or pinned to a trusted repository and release asset.

The updater validates the manifest schema and HTTPS origin, downloads to a fresh staging path, checks byte length and SHA-256, then moves the immutable file into games. It atomically replaces state.json only after the file is fully verified. On any failure, it retains the old active state and package. Rollback chooses a retained verified package, checks its hash again, and updates the pointer only while the game is stopped. A crash before pointer update leaves the previous active version valid. A crash after pointer update leaves the new complete package available.

## Multiplayer gate

The server pins one immutable PVE release and advertises exact gameName, version and SHA-256 in a separate trusted status endpoint or signed room metadata. The client launcher downloads and verifies that exact release before joining. The server changes its SPADS hosting preset to an exact escaped modName and verifies unitsync discovers exactly that archive; it must not keep the current official-test regex when hosting PVE. SPADS and engine should also enforce matching game archive checksums during game join. Treat launcher preflight as an early user-facing check, not the sole server-side security gate.

The server should switch to a new package only while its room is empty and no game process is running. Archive retention and SPADS restart/rescan must be coordinated. Rollback pins the previous immutable version, rescans archives, and only then reopens the room.

## First-phase boundaries

Do not edit the running SPADS configuration, official client data, launcher Program.cs, its PowerShell business scripts, or the RecoilEngine in this stage. Next integration stage can add a new updater script and a three-mode selector to the existing WinForms application, with the official button preserving its current call path. The development mode should use a separate isolation root and explicit source path; it must never be advertised as a release to public clients.

## Validation gates

1. Build source archive; unitsync reports only BAR PVE <version> and no duplicate game identity.
2. Server-only isolated run starts with exact GameType, no missing archive, and logs the expected game archive checksum.
3. Two clients with the release package join; a mismatched or missing package is stopped before room start and cannot pass engine archive checks.
4. Simulate corrupt download, truncated download and interrupted activation; state still points to a valid previous version.
5. During a running match, stage a newer release and verify neither active state nor current package changes; activate after exit.
6. Roll back to the retained previous version and repeat join validation.
7. Official launcher/update smoke test shows original behavior and files unchanged.

## Validation record: 2026-10-27

Environment: Windows PowerShell 5.1, local temporary fixture packages, no running Spring process. Parsed both new scripts with PowerShell Parser and found no syntax errors. Installed fixture 0.1.0-dev.1 and 0.1.0-dev.2, rolled back to dev.1, and confirmed state.json active=dev.1. A dev.3 manifest with a deliberately wrong SHA-256 was rejected and left dev.1 active. The package builder rejected the empty recoil-lua-library submodule as intended.

This does not establish that Spring/unitsync can load the PVE game. No real package, GitHub Release, server pin, launcher selector, multiplayer version gate, or in-game update check has been deployed. Those require submodule initialization, archive recognition and isolated server/client runtime validation. Existing server configuration and friend-launcher business code were not changed.
