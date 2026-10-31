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
