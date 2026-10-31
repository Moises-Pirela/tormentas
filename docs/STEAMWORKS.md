# Steamworks and submission rights

No permission or terms authorizing the previously bundled Steamworks material
for inclusion in a training submission were present. Its Valve copyright notice
was not evidence of such permission. We therefore removed the bundled changelog,
Odin binding and import libraries from the submitted source. The project's MIT
license does not grant rights to Valve's SDK.

Local originals are retained only in ignored `.local/` for private development.
Do not upload this directory. DLLs, shared libraries, executables, build output
and `.git/` are also excluded from the source submission archive. **Existing Git
history still contains the former Steamworks files.** Deleting them from the
working tree does not remove old commits. Submit the source archive below unless
the reviewer separately clears sharing that historical material. Do not upload a
raw copy of this folder or its Git history as the cleaned submission.

## Optional local Steam development

The previous integration targeted **Steamworks SDK 1.60**. Obtain it through
Valve's [official SDK page](https://partner.steamgames.com/doc/sdk) and
[partner downloads](https://partner.steamgames.com/downloads/list), using an account
authorized to access it and accepting the terms Valve presents there. Those terms
and any separate agreement with Valve govern SDK usage. These acquisition links
are not a redistribution permission letter.

An optional Steam collection must contain:

```text
<collection>/steamworks/steamworks.odin
<collection>/steamworks/redistributable_bin/win64/steam_api64.lib
<collection>/steamworks/redistributable_bin/win64/steam_api64.dll
```

Supply a compatible Odin binding you are authorized to use, or generate one from
your licensed SDK. The removed binding has no verified public redistribution
license or public download. It is intentionally outside the reproducible default
setup. The private local copy remains available for development. Copy the Windows
x64 library files from your separately acquired SDK into that private layout.

```powershell
.\build.ps1 -EnableSteam -SteamCollection 'C:\private\steam-collection'
```

For the preserved local copy, use `.\build.ps1 -EnableSteam`. The build copies
`steam_api64.dll` beside the executable. For direct development launches, place
your authorized development App ID in ignored `bin/steam_appid.txt`, following
Valve's [API setup guide](https://partner.steamgames.com/doc/sdk/api). Run the
Steam client for Steam features. Automated tests use the disabled transport.

## Clean training submission

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/export-source.ps1`.
It creates `dist/tormentas-source.zip` from current source, including uncommitted
fixes, tests, clockwork and documentation. It excludes the old SDK, private local
copies, Git history and generated binaries. Inspect and share that archive.
Other pre-existing assets and the Clay library still need to satisfy your
submission program's rules; this change does not certify rights to every asset.
