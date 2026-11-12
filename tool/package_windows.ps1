param(
    [ValidateSet('x64', 'arm64')][string]$Arch = 'x64',
    [string]$Label = 'v0.12',
    [string]$Compiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dist = Join-Path $repo 'dist'
$source = Join-Path $repo "build\windows\$Arch\runner\Release"
$labelSafe = $Label -replace '[^a-zA-Z0-9._-]', '-'
$artifact = "Flutify-$labelSafe-windows-$Arch"
$stage = [IO.Path]::GetFullPath((Join-Path $dist "$artifact-portable"))
if (!$stage.StartsWith($dist + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Staging path escaped dist'
}
if (!(Test-Path -LiteralPath $Compiler -PathType Leaf)) { throw "Inno Setup compiler not found: $Compiler" }
if (!(Test-Path -LiteralPath (Join-Path $source 'Flutify.exe'))) { throw "Missing release build: $source" }
if (!(Test-Path -LiteralPath (Join-Path $source 'data\app.so'))) { throw 'Missing release AOT library' }
if (Test-Path -LiteralPath $stage) {
    if ((Get-Item -LiteralPath $stage).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Staging path is a link' }
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
# Copy only Flutter distribution files. A previously launched build can have a
# WebView2 user profile beside the executable; never include that profile.
Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -in '.exe', '.dll' } |
    Copy-Item -Destination $stage
Copy-Item -LiteralPath (Join-Path $source 'data') -Destination $stage -Recurse
# Flutter can leave a debug kernel in the shared asset directory after a debug
# build. Release uses data/app.so; do not distribute debug snapshots or sources.
foreach ($name in 'kernel_blob.bin', 'vm_snapshot_data', 'isolate_snapshot_data') {
    $debugAsset = Join-Path $stage "data\flutter_assets\$name"
    if (Test-Path -LiteralPath $debugAsset -PathType Leaf) {
        Remove-Item -LiteralPath $debugAsset -Force
    }
}
if (Test-Path -LiteralPath (Join-Path $source 'native_assets.json')) {
    Copy-Item -LiteralPath (Join-Path $source 'native_assets.json') -Destination $stage
}
foreach ($name in 'LICENSE', 'THIRD_PARTY_NOTICES.md') {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $stage
}
$versionLine = Select-String -LiteralPath (Join-Path $repo 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)'
$version = $versionLine.Matches[0].Groups[1].Value
& $Compiler "/DAppVersion=$version" "/DAppArch=$Arch" "/DBuildDir=$stage" "/DOutputPath=$dist" "/DArtifactName=$artifact" (Join-Path $repo 'windows\installer\flutify.iss')
if ($LASTEXITCODE -ne 0) { throw "Installer compiler failed: $LASTEXITCODE" }
$zip = Join-Path $dist "$artifact.zip"
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
Get-Item -LiteralPath $zip, (Join-Path $dist "$artifact-setup.exe") | Select-Object FullName, Length
