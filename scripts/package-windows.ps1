[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][ValidatePattern('^v[0-9A-Za-z.-]+$')][string]$Tag,
    [string]$Compiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bundle = Join-Path $root 'app/build/windows/x64/runner/Release'
$output = Join-Path $root 'dist'
if (!(Test-Path -LiteralPath "$bundle/album_manager.exe")) { throw 'Build the Windows release first.' }
if (!(Test-Path -LiteralPath $Compiler)) { throw "Inno Setup 6 compiler not found: $Compiler" }

# Ship app-local release CRT DLLs so a fresh Windows installation can run the app
# without a separate, administrator-only Visual C++ runtime installation.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Visual Studio C++ tools not found.' }
$redist = Join-Path $vs 'VC/Redist/MSVC'
$versions = Get-ChildItem -LiteralPath $redist -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending
$crt = $versions | ForEach-Object {
    Get-ChildItem -Path (Join-Path $_.FullName 'x64/Microsoft.VC*.CRT') -Directory
} | Select-Object -First 1
if (!$crt) { throw 'Redistributable x64 Visual C++ runtime not found.' }
Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $bundle
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (!(Test-Path -LiteralPath "$bundle/$dll")) { throw "Missing runtime: $dll" }
}
Copy-Item -LiteralPath "$root/LICENSE" -Destination "$bundle/LICENSE.txt"
Copy-Item -LiteralPath "$root/README.md" -Destination "$bundle/README.md"
New-Item -ItemType Directory -Path $output -Force | Out-Null
Compress-Archive -Path "$bundle/*" -DestinationPath "$output/AlbumManager-$Tag-windows-x64.zip" -Force
& $Compiler "/DAppVersion=$Version" "/DReleaseTag=$Tag" "/DBundleDir=$bundle" "/DOutputDir=$output" "$PSScriptRoot/windows-installer.iss"
if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed: $LASTEXITCODE" }
if (!(Test-Path -LiteralPath "$output/AlbumManager-$Tag-windows-x64-setup.exe")) {
    throw 'Installer output is missing.'
}
