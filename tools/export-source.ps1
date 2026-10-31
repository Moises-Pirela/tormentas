$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-ClockworkSnapshot
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path (Join-Path $Root 'dist') -Force | Out-Null
$Zip = Join-Path $Root 'dist\tormentas-source.zip'
$Files = @()
foreach ($Dir in 'src', 'data', 'tools', 'clay', 'deps', 'ui', 'docs', '.github') {
    $Path = Join-Path $Root $Dir
    if (Test-Path -LiteralPath $Path) { $Files += Get-ChildItem -LiteralPath $Path -Recurse -File }
}
foreach ($Name in 'README.md', 'LICENSE', 'TUNING.md', 'ROADMAP.md', '.gitignore', '.gitattributes', 'ols.json', 'toolchain.json', 'build.ps1', 'build.bat', 'run.bat', 'test.ps1', 'test.bat') {
    $Files += Get-Item -LiteralPath (Join-Path $Root $Name)
}
$Stream = [IO.File]::Open($Zip, [IO.FileMode]::Create)
$Archive = New-Object System.IO.Compression.ZipArchive($Stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($File in ($Files | Sort-Object FullName -Unique)) {
        $Relative = $File.FullName.Substring($Root.Length + 1).Replace('\', '/')
        if ($Relative -match '(^|/)(\.git|\.local|__pycache__)(/|$)' -or
            $File.Name -match '^steam_api' -or
            $File.Extension -in '.exe', '.dll', '.so', '.dylib', '.pdb', '.pyc', '.zip' -or
            ($File.Extension -eq '.lib' -and $Relative -ne 'clay/windows/clay.lib')) { continue }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $File.FullName, $Relative, [IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $Archive.Dispose()
    $Stream.Dispose()
}
Write-Host "[SOURCE] $Zip"
