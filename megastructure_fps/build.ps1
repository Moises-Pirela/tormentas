param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug'
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src  = Join-Path $Root 'src'
$Bin  = Join-Path $Root 'bin'
$Out  = Join-Path $Bin 'megastructure_fps.exe'
$Odin = 'C:\ODIN\odin.exe'

New-Item -ItemType Directory -Force -Path $Bin | Out-Null

if ($Mode -eq 'release') {
    Write-Host '[BUILD] Release : -o:aggressive'
    & $Odin build $Src "-out:$Out" '-o:aggressive'
} else {
    Write-Host '[BUILD] Debug : -o:none -debug -vet'
    & $Odin build $Src "-out:$Out" '-o:none' '-debug' '-vet'
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host "[BUILD] FAILED  (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host "[BUILD] OK  ->  $Out"

