[CmdletBinding()]
param([string]$PublishDir = '.build/windows/publish', [string]$BuildDir = '.build/windows')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$PublishDir = [IO.Path]::GetFullPath($PublishDir, $root)
$BuildDir = [IO.Path]::GetFullPath($BuildDir, $root)
$cache = Join-Path $BuildDir 'downloads'
$tools = Join-Path $PublishDir 'tools'
$notices = Join-Path $PublishDir 'ThirdParty'
New-Item -ItemType Directory -Force $cache, $tools, $notices, "$BuildDir/evidence" | Out-Null
$lockPath = Join-Path $root 'windows/packaging/dependencies.lock.json'
$lock = Get-Content $lockPath -Raw | ConvertFrom-Json
foreach ($item in $lock.downloads) {
    if ($item.name -notmatch '^[A-Za-z0-9_.-]+$' -or $item.sha256 -notmatch '^[0-9a-f]{64}$' -or $item.url -notlike 'https://*') { throw 'Invalid dependency lock entry' }
    $target = Join-Path $cache $item.name
    if (Test-Path $target) {
        if ((Get-FileHash $target -Algorithm SHA256).Hash -ine $item.sha256) { Remove-Item $target -Force }
    }
    if (!(Test-Path $target)) {
        $partial = "$target.partial"
        try {
            Invoke-WebRequest -Uri $item.url -OutFile $partial -MaximumRetryCount 3 -RetryIntervalSec 3 -TimeoutSec 300
            if ((Get-FileHash $partial -Algorithm SHA256).Hash -ine $item.sha256) { throw "SHA256 mismatch: $($item.name)" }
            Move-Item $partial $target -Force
        } finally { if (Test-Path $partial) { Remove-Item $partial -Force } }
    }
    if ($item.kind -eq 'tool') { Copy-Item $target $tools -Force }
    if ($item.kind -eq 'notice') { Copy-Item $target $notices -Force }
    if ($item.kind -eq 'deno') {
        $unpack = Join-Path $BuildDir 'deno-unpack'
        if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
        Expand-Archive $target $unpack
        if (!(Test-Path "$unpack/deno.exe")) { throw 'Deno archive lacks deno.exe' }
        Copy-Item "$unpack/deno.exe" $tools -Force
    }
}
Copy-Item $lockPath "$notices/dependencies.lock.json" -Force
Copy-Item "$root/windows/packaging/THIRD_PARTY_NOTICES.md" "$PublishDir/THIRD_PARTY_NOTICES.md" -Force
Copy-Item $lockPath "$BuildDir/evidence/dependencies.lock.json" -Force
Write-Host 'Verified downloads prepared. Next run scripts/windows/build-ffmpeg.sh in MSYS2 MINGW64.'
