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
$Cw   = Join-Path (Split-Path -Parent $Root) 'clockwork-ecs'

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'bin') | Out-Null

if (-not (Test-Path (Join-Path $Cw 'clockwork'))) {
    Write-Host "[BUILD] clockwork-ecs not found at $Cw"
    exit 1
}

if ($Mode -eq 'release') {
    Write-Host '[BUILD] Release : -o:aggressive -subsystem:windows'
    & $Odin build $Src "-out:$Out" "-collection:cw=$Cw" '-o:aggressive' '-subsystem:windows' "-resource:$Res"
} else {
    Write-Host '[BUILD] Debug : -o:none -debug -vet'
    & $Odin build $Src "-out:$Out" "-collection:cw=$Cw" '-o:none' '-debug' '-vet' "-resource:$Res"
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

foreach ($stale in 'data', 'save') {
    $p = Join-Path $Dist $stale
    if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue }
}

Copy-Item -Force $Out (Join-Path $Dist 'tormentas.exe')
Copy-Item -Recurse -Force (Join-Path $Root 'data') (Join-Path $Dist 'data')

New-Item -ItemType Directory -Force -Path (Join-Path $Dist 'save') | Out-Null

foreach ($f in 'steam_api64.dll', 'steam_appid.txt') {
    $srcF = Join-Path $Root ('bin\' + $f)
    if (Test-Path $srcF) {
        Copy-Item -Force $srcF (Join-Path $Dist $f)
    } else {
        Write-Host "[PACKAGE] Warning: $f not found in bin - build may fail to launch / lack Steam"
    }
}

Write-Host '[PACKAGE] Done'
Write-Host ''
Write-Host '  dist\tormentas\'
Write-Host '    tormentas.exe'
Write-Host '    steam_api64.dll'
Write-Host '    steam_appid.txt'
Write-Host '    data\'
Write-Host '    save\'

$Stamp = Get-Date -Format 'yyyy-MM-dd'
$Zip   = Join-Path $Root ('dist\tormentas_' + $Stamp + '.zip')
if (Test-Path $Zip) { Remove-Item -Force $Zip }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$DistParent = Split-Path $Dist -Parent
$archive    = [System.IO.Compression.ZipFile]::Open($Zip, 'Create')
try {
    foreach ($f in Get-ChildItem -Path $Dist -Recurse -File) {
        $rel = $f.FullName.Substring($DistParent.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
}

Write-Host ''
Write-Host "[PACKAGE] Zipped  ->  $Zip"
