$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-Odin([string]$Requested) {
    if (-not $Requested) { $Requested = $env:ODIN }
    if (-not $Requested) { $Requested = 'odin' }
    $Compiler = (Get-Command $Requested -ErrorAction Stop).Source
    $Lock = Get-Content -LiteralPath (Join-Path $RepoRoot 'toolchain.json') -Raw | ConvertFrom-Json
    $Version = & $Compiler version
    if ($LASTEXITCODE -ne 0 -or $Version -notmatch [regex]::Escape($Lock.odin_revision)) {
        throw "Expected Odin $($Lock.odin_release) revision $($Lock.odin_revision); found $Version. See docs/SETUP.md."
    }
    return $Compiler
}

function Assert-ImGuiSnapshot {
    $Base = Join-Path $RepoRoot 'deps\imgui'
    $Snapshot = Get-Content -LiteralPath (Join-Path $Base 'snapshot.json') -Raw | ConvertFrom-Json
    foreach ($Entry in @($Snapshot.sha256.PSObject.Properties)) {
        $File = Join-Path $Base ($Entry.Name -replace '/', '\')
        if (-not (Test-Path -LiteralPath $File)) { throw "imgui snapshot file missing: $($Entry.Name)" }
        if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Entry.Value) {
            throw "imgui snapshot mismatch: $($Entry.Name)"
        }
    }
}

function Assert-ClockworkSnapshot {
    $Base = Join-Path $RepoRoot 'deps\clockwork-ecs'
    $Snapshot = Get-Content -LiteralPath (Join-Path $Base 'snapshot.json') -Raw | ConvertFrom-Json
    $Files = @(Get-ChildItem -LiteralPath (Join-Path $Base 'clockwork') -Filter '*.odin' -File)
    $Entries = @($Snapshot.sha256.PSObject.Properties)
    if ($Files.Count -ne $Entries.Count) { throw 'clockwork snapshot file count differs from snapshot.json.' }
    foreach ($Entry in $Entries) {
        $File = Join-Path $Base ('clockwork\' + $Entry.Name)
        if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Entry.Value) {
            throw "clockwork snapshot mismatch: $($Entry.Name)"
        }
    }
}

# ---- sokol (P1a). Mirrors the sokol helpers in tools/common.sh. --------------------------------

$SokolModules = @('log', 'gfx', 'app', 'glue', 'time', 'gl', 'shape')

function Assert-SokolSnapshot {
    # Every vendored binding/header must match deps/sokol/snapshot.json, and nothing unlisted may sneak in.
    $Base = Join-Path $RepoRoot 'deps\sokol'
    $Snapshot = Get-Content -LiteralPath (Join-Path $Base 'snapshot.json') -Raw | ConvertFrom-Json
    $Entries = @($Snapshot.sha256.PSObject.Properties)
    foreach ($Entry in $Entries) {
        $File = Join-Path $Base ($Entry.Name -replace '/', '\')
        if (-not (Test-Path -LiteralPath $File)) { throw "sokol snapshot file missing: $($Entry.Name)" }
        if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Entry.Value) {
            throw "sokol snapshot mismatch: $($Entry.Name)"
        }
    }
    $Files = @(Get-ChildItem -LiteralPath (Join-Path $Base 'sokol') -Recurse -File |
        Where-Object { $_.Extension -in '.odin', '.c', '.h' })
    $Listed = @($Entries | Where-Object { $_.Name -like 'sokol/*' })
    if ($Files.Count -ne $Listed.Count) {
        throw "sokol snapshot file count ($($Files.Count)) differs from snapshot.json ($($Listed.Count))."
    }
}

function Use-MsvcEnvironment {
    # Makes cl.exe and lib.exe available: as-is from a Developer PowerShell, otherwise through the
    # Visual Studio C++ build tools that docs/SETUP.md already requires (found with vswhere).
    if ((Get-Command cl.exe -ErrorAction SilentlyContinue) -and (Get-Command lib.exe -ErrorAction SilentlyContinue)) { return }
    $Vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $Vswhere)) {
        throw 'cl.exe not found and vswhere.exe is missing. Install the C++ build tools (docs/SETUP.md) or run from a Developer PowerShell.'
    }
    $Install = & $Vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $Install) { throw 'No Visual Studio installation with the C++ x64 tools was found (docs/SETUP.md).' }
    $Vcvars = Join-Path $Install 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path -LiteralPath $Vcvars)) { throw "vcvars64.bat not found: $Vcvars" }
    # A temporary .cmd avoids Windows PowerShell 5.1's quoting rules for native arguments.
    $Probe = Join-Path ([IO.Path]::GetTempPath()) ("tormentas-vcvars-" + [Guid]::NewGuid().ToString('N') + '.cmd')
    Set-Content -LiteralPath $Probe -Encoding ASCII -Value "@call `"$Vcvars`" >nul`r`n@set"
    try {
        $Lines = & cmd.exe /d /c $Probe
        if ($LASTEXITCODE -ne 0) { throw "vcvars64.bat failed ($LASTEXITCODE)" }
    } finally {
        Remove-Item -LiteralPath $Probe -Force -ErrorAction SilentlyContinue
    }
    foreach ($Line in $Lines) {
        if ($Line -match '^([^=]+)=(.*)$') { Set-Item -LiteralPath "Env:$($Matches[1])" -Value $Matches[2] }
    }
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'cl.exe still not found after vcvars64.bat.' }
}

function Initialize-SokolLibs {
    # Builds the sokol D3D11 static libraries if any is missing or older than the manifest or builder.
    $Base = Join-Path $RepoRoot 'deps\sokol\sokol'
    $Inputs = @((Join-Path $RepoRoot 'deps\sokol\snapshot.json'), (Join-Path $RepoRoot 'tools\build-sokol.ps1'))
    $Newest = ($Inputs | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks } | Measure-Object -Maximum).Maximum
    $Stale = $false
    foreach ($M in $SokolModules) {
        foreach ($Mode in 'debug', 'release') {
            $Lib = Join-Path $Base "$M\sokol_${M}_windows_x64_d3d11_$Mode.lib"
            if (-not (Test-Path -LiteralPath $Lib) -or (Get-Item -LiteralPath $Lib).LastWriteTimeUtc.Ticks -lt $Newest) { $Stale = $true }
        }
    }
    if ($Stale) { & (Join-Path $RepoRoot 'tools\build-sokol.ps1') } else { Assert-SokolSnapshot }
}

function Initialize-Shdc {
    # Downloads the pinned sokol-shdc into .local\sokol-shdc\<commit>\ (once), verifies it, returns its path.
    $Pin = (Get-Content -LiteralPath (Join-Path $RepoRoot 'deps\sokol\snapshot.json') -Raw | ConvertFrom-Json).sokol_shdc
    $Plat = $Pin.platforms.windows_amd64
    $Dest = Join-Path $RepoRoot ".local\sokol-shdc\$($Pin.commit)\sokol-shdc.exe"
    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
        $Url = "https://raw.githubusercontent.com/floooh/sokol-tools-bin/$($Pin.commit)/$($Plat.path)"
        Write-Host "[SHDC] downloading sokol-shdc $($Pin.commit) (windows_amd64)"
        # Windows PowerShell 5.1 may not offer TLS 1.2 by default; GitHub requires it.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $Part = "$Dest.part"
        Invoke-WebRequest -Uri $Url -OutFile $Part -UseBasicParsing
        $Actual = (Get-FileHash -LiteralPath $Part -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Actual -ne $Plat.sha256) { Remove-Item -LiteralPath $Part -Force; throw "sokol-shdc hash mismatch: got $Actual" }
        Move-Item -LiteralPath $Part -Destination $Dest
    }
    if ((Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Plat.sha256) {
        throw "sokol-shdc at $Dest does not match snapshot.json"
    }
    return $Dest
}

function Invoke-ShaderCompile([string]$Dir) {
    # Regenerates <name>.glsl.odin next to every <name>.glsl under $Dir that is newer than its output.
    # Targets the two decided backends: Metal (macOS) and D3D11 (Windows).
    $Shdc = $null
    foreach ($Src in @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter '*.glsl' | Sort-Object FullName)) {
        $Out = "$($Src.FullName).odin"
        if (-not (Test-Path -LiteralPath $Out) -or $Src.LastWriteTimeUtc -gt (Get-Item -LiteralPath $Out).LastWriteTimeUtc) {
            if (-not $Shdc) { $Shdc = Initialize-Shdc }
            Write-Host "[SHDC] $($Src.FullName) -> $Out"
            & $Shdc -i $Src.FullName -o $Out -l 'metal_macos:hlsl5' -f sokol_odin
            if ($LASTEXITCODE -ne 0) { throw "sokol-shdc failed on $($Src.FullName)" }
        }
    }
}
