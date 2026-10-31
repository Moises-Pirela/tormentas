param([string]$OdinPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Odin = Resolve-Odin $OdinPath
Assert-ClockworkSnapshot
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot 'bin') | Out-Null
$Cw = Join-Path $RepoRoot 'deps\clockwork-ecs'
$Offline = Join-Path $RepoRoot 'deps\offline'
foreach ($Suite in @(
    @{ Path = 'deps\clockwork-ecs\clockwork'; Name = 'clockwork' },
    @{ Path = 'src\p2p'; Name = 'protocol' },
    @{ Path = 'src'; Name = 'game' }
)) {
    & $Odin test (Join-Path $RepoRoot $Suite.Path) "-collection:cw=$Cw" "-collection:steam=$Offline" '-vet' '-linker:lld' '-define:ODIN_TEST_THREADS=1' "-out:$(Join-Path $RepoRoot ('bin\' + $Suite.Name + '_tests.exe'))"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
