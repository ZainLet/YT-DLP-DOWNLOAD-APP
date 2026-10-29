[CmdletBinding()]
param([string]$BuildDir = '.build/windows', [string]$Version = '1.3.0-beta.1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$BuildDir = [IO.Path]::GetFullPath($BuildDir, $root)
$evidence = Join-Path $BuildDir 'evidence'
$dist = Join-Path $BuildDir 'dist'
$prefix = "YTDLP-Studio-$Version-win-x64"
$portable = Join-Path $BuildDir 'portable test'
$installed = Join-Path $env:LOCALAPPDATA "Programs/YTDLP Studio CI $([guid]::NewGuid().ToString('N'))"
function Assert-Manifest([string]$Directory) {
    $manifest = Get-Content "$Directory/publish-manifest.json" -Raw | ConvertFrom-Json
    foreach ($entry in $manifest) {
        $path = Join-Path $Directory $entry.path
        if (!(Test-Path $path) -or (Get-FileHash $path -Algorithm SHA256).Hash -ine $entry.sha256) { throw "Package content mismatch: $($entry.path)" }
    }
}
function Invoke-Smoke([string]$Exe, [string]$OutputDirectory) {
    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    $p = Start-Process $Exe -ArgumentList @('--smoke-test', ('"' + $OutputDirectory + '"')) -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Packaged smoke test failed: $($p.ExitCode)" }
    Get-Content "$OutputDirectory/smoke-result.json" -Raw | ConvertFrom-Json | Out-Null
    if (@(Get-ChildItem $OutputDirectory -Filter '*.png' -Recurse).Count -lt 5) { throw 'Packaged smoke lacks five GUI screenshots' }
}
foreach ($line in Get-Content "$dist/SHA256SUMS") {
    if ($line -notmatch '^([a-f0-9]{64})  ([A-Za-z0-9_.-]+)$') { throw 'Invalid SHA256SUMS line' }
    if ((Get-FileHash (Join-Path $dist $Matches[2]) -Algorithm SHA256).Hash -ine $Matches[1]) { throw 'Distribution checksum mismatch' }
}
if (Test-Path $portable) { Remove-Item $portable -Recurse -Force }
Expand-Archive "$dist/$prefix-Portable.zip" $portable
Assert-Manifest $portable
Invoke-Smoke "$portable/YTDLPStudio.exe" "$evidence/portable-smoke"
$setupExe = "$dist/$prefix-Setup.exe"
try {
    $p = Start-Process $setupExe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CURRENTUSER', ('/DIR="' + $installed + '"'), ('/LOG="' + "$evidence/install.log" + '"')) -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Install failed: $($p.ExitCode)" }
    Assert-Manifest $installed
    Invoke-Smoke "$installed/YTDLPStudio.exe" "$evidence/installed-smoke"
    $key = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/{65863B76-8CB1-4308-81ED-FA8409CA650A}_is1'
    $registration = Get-ItemProperty $key
    if ([IO.Path]::GetFullPath($registration.InstallLocation).TrimEnd('\') -ine $installed.TrimEnd('\')) { throw 'Installer registration is not per-user or points at another directory' }
    $registration | Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString | ConvertTo-Json | Set-Content "$evidence/install-registration.json"
} finally {
    $uninstaller = "$installed/uninstall/unins000.exe"
    if (Test-Path $uninstaller) {
        $p = Start-Process $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="' + "$evidence/uninstall.log" + '"')) -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Uninstall failed: $($p.ExitCode)" }
    }
}
if (Test-Path "$installed/YTDLPStudio.exe") { throw 'Uninstall left application executable' }
if (Test-Path $key) { throw 'Uninstall left HKCU registration' }
@{ success = $true; portableManifestVerified = $true; installedManifestVerified = $true; perUserRegistrationVerified = $true; uninstallVerified = $true } | ConvertTo-Json | Set-Content "$evidence/distribution-result.json"
