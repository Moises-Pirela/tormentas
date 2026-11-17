# usage: .\build.ps1 [debug|release] [-Target game|spike] [-OdinPath PATH] [-EnableSteam] [-SteamCollection DIR]
#   game   (default) -> bin\tormentas.exe; release also packages dist\tormentas-release.zip
#   spike  P1a sokol spike (D3D11), throwaway -> bin\tormentas_spike.exe
param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug',
    [ValidateSet('game', 'spike')]
    [string]$Target = 'game',
    [string]$OdinPath,
    [switch]$EnableSteam,
    [string]$SteamCollection = (Join-Path $PSScriptRoot '.local')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Odin = Resolve-Odin $OdinPath
if ($Target -eq 'spike') {
    # P1a step 1 (docs/BUILD_PLAN.md): sokol + shdc + D3D11 readback, isolated from the game.
    Initialize-SokolLibs
    Invoke-ShaderCompile (Join-Path $RepoRoot 'src\spike')
    $SpikeFlags = @('-o:none', '-debug', '-vet')
    if ($Mode -eq 'release') { $SpikeFlags = @('-o:aggressive', '-vet') }
    $SpikeOut = Join-Path $RepoRoot 'bin\tormentas_spike.exe'
    New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot 'bin') | Out-Null
    & $Odin build (Join-Path $RepoRoot 'src\spike') "-out:$SpikeOut" "-collection:sokol=$(Join-Path $RepoRoot 'deps\sokol\sokol')" '-linker:lld' @SpikeFlags
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "[BUILD] OK -> $SpikeOut (run it from the repository root: it loads data\ relative to the working directory)"
    exit 0
}
Assert-ClockworkSnapshot
Assert-ImGuiSnapshot
$Root = $RepoRoot
$Out = Join-Path $Root 'bin\tormentas.exe'
$Cw = Join-Path $Root 'deps\clockwork-ecs'
$Steam = Join-Path $Root 'deps\offline'
$Flags = @('-o:none', '-debug', '-vet')
if ($Mode -eq 'release') { $Flags = @('-o:aggressive', '-subsystem:windows', '-vet') }
if ($EnableSteam) {
    $Steam = (Resolve-Path -LiteralPath $SteamCollection).Path
    foreach ($Required in 'steamworks\steamworks.odin', 'steamworks\redistributable_bin\win64\steam_api64.lib', 'steamworks\redistributable_bin\win64\steam_api64.dll') {
        if (-not (Test-Path -LiteralPath (Join-Path $Steam $Required))) {
            throw "Missing optional Steam dependency: $Required. See docs/STEAMWORKS.md."
        }
    }
    $Flags += '-define:STEAM_ENABLED=true'
}
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'bin') | Out-Null
& $Odin build (Join-Path $Root 'src') "-out:$Out" "-collection:cw=$Cw" "-collection:steam=$Steam" '-linker:lld' "-resource:$(Join-Path $Root 'data\app\tormentas.rc')" @Flags
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($EnableSteam) {
    Copy-Item -LiteralPath (Join-Path $Steam 'steamworks\redistributable_bin\win64\steam_api64.dll') -Destination (Join-Path $Root 'bin\steam_api64.dll') -Force
}
Write-Host "[BUILD] OK -> $Out (Steam enabled: $EnableSteam)"
if ($Mode -ne 'release') { exit 0 }
$Dist = [IO.Path]::GetFullPath((Join-Path $Root 'dist\tormentas'))
if (-not $Dist.StartsWith($Root + [IO.Path]::DirectorySeparatorChar)) { throw 'Invalid distribution path' }
if (Test-Path -LiteralPath $Dist) { Remove-Item -LiteralPath $Dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Copy-Item -LiteralPath $Out -Destination (Join-Path $Dist 'tormentas.exe')
Copy-Item -LiteralPath (Join-Path $Root 'data') -Destination (Join-Path $Dist 'data') -Recurse
Copy-Item -LiteralPath (Join-Path $Root 'LICENSE') -Destination $Dist
if ($EnableSteam) { Copy-Item -LiteralPath (Join-Path $Root 'bin\steam_api64.dll') -Destination $Dist }
$Zip = Join-Path $Root 'dist\tormentas-release.zip'
Compress-Archive -LiteralPath $Dist -DestinationPath $Zip -Force
Write-Host "[PACKAGE] $Zip"
