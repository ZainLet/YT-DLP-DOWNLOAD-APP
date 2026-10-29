[CmdletBinding()]
param([string]$PublishDir = '.build/windows/publish', [string]$BuildDir = '.build/windows', [string]$Version = '1.3.0-beta.1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$PublishDir = [IO.Path]::GetFullPath($PublishDir, $root)
$BuildDir = [IO.Path]::GetFullPath($BuildDir, $root)
if ($Version -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$') { throw 'Invalid package version' }
$dist = Join-Path $BuildDir 'dist'
$evidence = Join-Path $BuildDir 'evidence'
$thirdParty = Join-Path $PublishDir 'ThirdParty'
New-Item -ItemType Directory -Force $dist, $evidence, $thirdParty | Out-Null
foreach ($file in @('YTDLPStudio.exe', 'YTDLPStudio.runtimeconfig.json', 'coreclr.dll', 'hostfxr.dll', 'PresentationFramework.dll', 'tools/ffmpeg.exe', 'tools/ffprobe.exe', 'tools/yt-dlp.exe', 'tools/deno.exe', 'THIRD_PARTY_NOTICES.md', 'ThirdParty/FFmpeg-LGPL-2.1.txt', 'ThirdParty/LAME-LICENSE.txt')) {
    if (!(Test-Path (Join-Path $PublishDir $file))) { throw "Incomplete self-contained publish: $file" }
}
$config = Get-Content "$PublishDir/YTDLPStudio.runtimeconfig.json" -Raw | ConvertFrom-Json
if (!$config.runtimeOptions.PSObject.Properties['includedFrameworks']) { throw 'App must be self-contained' }
$ffmpegLicense = & "$PublishDir/tools/ffmpeg.exe" -L 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $ffmpegLicense -notmatch 'GNU Lesser General Public License' -or $ffmpegLicense -match '--enable-gpl|--enable-nonfree') { throw 'Expected LGPL-only FFmpeg' }
# Preserve the framework distribution's own full notices, in addition to app/tool notices.
$dotnetRoot = Split-Path (Get-Command dotnet).Source
$frameworkNotices = @(Get-ChildItem "$dotnetRoot/shared" -Recurse -File | Where-Object { $_.Name -match '^(LICENSE\.txt|ThirdPartyNotices\.txt)$' })
if (!$frameworkNotices) { throw 'Missing .NET framework license/third-party notices' }
foreach ($notice in $frameworkNotices) {
    $relative = [IO.Path]::GetRelativePath($dotnetRoot, $notice.FullName)
    $target = Join-Path "$thirdParty/dotnet" $relative
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item $notice.FullName $target -Force
}
$sources = Join-Path $thirdParty 'Sources'
New-Item -ItemType Directory -Force $sources | Out-Null
$lock = Get-Content "$root/windows/packaging/dependencies.lock.json" -Raw | ConvertFrom-Json
foreach ($item in $lock.downloads | Where-Object kind -eq 'source') {
    $source = Join-Path "$BuildDir/downloads" $item.name
    if ((Get-FileHash $source -Algorithm SHA256).Hash -ine $item.sha256) { throw "Source hash mismatch: $($item.name)" }
    Copy-Item $source $sources -Force
}
Copy-Item "$root/scripts/windows/build-ffmpeg.sh" $sources -Force
Copy-Item "$root/scripts/windows/prepare-runtime.ps1" $sources -Force
Copy-Item "$root/windows/packaging/dependencies.lock.json" $sources -Force
Copy-Item "$root/windows/packaging/SOURCE_BUILD.md" $sources -Force
Copy-Item "$thirdParty/FFmpeg-BUILD-CONFIG.txt" $sources -Force
# Both installer and portable include the corresponding sources; also supply a separate source artifact.
$prefix = "YTDLP-Studio-$Version-win-x64"
Compress-Archive -Path "$sources/*" -DestinationPath "$dist/$prefix-ThirdPartySources.zip" -Force
$manifest = @(Get-ChildItem $PublishDir -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path = [IO.Path]::GetRelativePath($PublishDir, $_.FullName).Replace('\', '/'); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); bytes = $_.Length }
})
$manifest | ConvertTo-Json -Depth 4 | Set-Content "$evidence/publish-manifest.json" -Encoding utf8
Copy-Item "$evidence/publish-manifest.json" "$PublishDir/publish-manifest.json" -Force
Compress-Archive -Path "$PublishDir/*" -DestinationPath "$dist/$prefix-Portable.zip" -CompressionLevel Optimal -Force
$innoDownload = Join-Path "$BuildDir/downloads" 'innosetup-6.5.4.exe'
$innoItem = $lock.downloads | Where-Object name -eq 'innosetup-6.5.4.exe'
if ((Get-FileHash $innoDownload -Algorithm SHA256).Hash -ine $innoItem.sha256) { throw 'Inno Setup hash mismatch' }
$innoDir = Join-Path $BuildDir 'inno'
$setupArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CURRENTUSER', ('/DIR="' + $innoDir + '"'), ('/LOG="' + "$evidence/inno-bootstrap.log" + '"'))
$setup = Start-Process $innoDownload -ArgumentList $setupArgs -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Inno bootstrap failed: $($setup.ExitCode)" }
& "$innoDir/ISCC.exe" "/DPublishDir=$PublishDir" "/DOutputDir=$dist" "/DAppVersion=$Version" "$root/windows/packaging/YTDLPStudio.iss" 2>&1 | Tee-Object "$evidence/inno-compile.log"
if ($LASTEXITCODE -ne 0) { throw 'Inno compilation failed' }
Get-ChildItem $dist -File | Where-Object Name -ne 'SHA256SUMS' | Sort-Object Name | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
} | Set-Content "$dist/SHA256SUMS" -Encoding ascii
Write-Host "Windows distributions: $dist"
