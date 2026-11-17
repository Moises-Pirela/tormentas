# Builds the sokol static libraries for Windows (D3D11) from the pinned headers in deps\sokol\sokol\c.
# Each binding in deps\sokol\sokol\<module>\ links sokol_<module>_windows_x64_d3d11_<mode>.lib,
# picking debug or release from ODIN_DEBUG, so both variants are built. Flags match upstream
# sokol-odin's build_clibs_windows.cmd. Counterpart of tools/build-sokol.sh.
#
# usage: tools\build-sokol.ps1 [-Force]
param([switch]$Force)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-SokolSnapshot
Use-MsvcEnvironment

$Base = Join-Path $RepoRoot 'deps\sokol\sokol'
$Inputs = @((Join-Path $RepoRoot 'deps\sokol\snapshot.json'), $PSCommandPath)
$Newest = ($Inputs | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks } | Measure-Object -Maximum).Maximum
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("tormentas-sokol-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
try {
    foreach ($Mode in 'debug', 'release') {
        $Flags = if ($Mode -eq 'debug') { @('/D_DEBUG', '/Z7') } else { @('/O2', '/DNDEBUG') }
        foreach ($M in $SokolModules) {
            $Out = Join-Path $Base "$M\sokol_${M}_windows_x64_d3d11_$Mode.lib"
            if (-not $Force -and (Test-Path -LiteralPath $Out) -and (Get-Item -LiteralPath $Out).LastWriteTimeUtc.Ticks -ge $Newest) { continue }
            Write-Host "[SOKOL] compiling sokol_$M (x64, $Mode)"
            $Obj = Join-Path $Tmp "sokol_${M}_$Mode.obj"
            & cl.exe /nologo /c @Flags /DIMPL /DSOKOL_D3D11 (Join-Path $Base "c\sokol_$M.c") "/Fo$Obj"
            if ($LASTEXITCODE -ne 0) { throw "cl.exe failed on sokol_$M.c ($Mode)" }
            if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }
            & lib.exe /nologo "/OUT:$Out" $Obj
            if ($LASTEXITCODE -ne 0) { throw "lib.exe failed for sokol_$M ($Mode)" }
        }
    }
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "[SOKOL] OK -> $Base\*\sokol_*_windows_x64_d3d11_{debug,release}.lib"
