param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug'
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src  = Join-Path $Root 'src'
$Out  = Join-Path $Root 'bin\tormentas.exe'
$Dist = Join-Path $Root 'dist\tormentas'
$Odin = 'C:\ODIN\odin.exe'
$Res  = Join-Path $Root 'data\app\tormentas.rc'

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'bin') | Out-Null

if ($Mode -eq 'release') {
    Write-Host '[BUILD] Release : -o:aggressive -subsystem:windows'
    & $Odin build $Src "-out:$Out" '-o:aggressive' '-subsystem:windows' "-resource:$Res"
} else {
    Write-Host '[BUILD] Debug : -o:none -debug -vet'
    & $Odin build $Src "-out:$Out" '-o:none' '-debug' '-vet' "-resource:$Res"
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host "[BUILD] FAILED  (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host "[BUILD] OK  ->  $Out"

$RootExe = Join-Path $Root 'tormentas.exe'
try {
    Copy-Item -Force $Out $RootExe
    Write-Host '[BUILD] Copied  ->  tormentas.exe'
} catch {
    Write-Host '[BUILD] Warning: could not refresh root tormentas.exe copy'
    Write-Host '[BUILD]          bin\tormentas.exe is the up-to-date build'
}

if ($Mode -ne 'release') {
    exit 0
}

Write-Host ''
Write-Host '[PACKAGE] Building dist\tormentas\ ...'

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
if (Test-Path (Join-Path $Dist 'data')) {
    Remove-Item -Recurse -Force (Join-Path $Dist 'data') -ErrorAction SilentlyContinue
}
Copy-Item -Force $Out (Join-Path $Dist 'tormentas.exe')
Copy-Item -Recurse -Force (Join-Path $Root 'data') (Join-Path $Dist 'data')

Write-Host '[PACKAGE] Done'
Write-Host ''
Write-Host '  dist\tormentas\'
Write-Host '    tormentas.exe'
Write-Host '    data\'
