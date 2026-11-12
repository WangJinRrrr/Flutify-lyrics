# Desktop lyrics smoke test for the Windows release build.
# ReproduceOld: v0.18-lyrics.1 must exit after the saved switch is turned on.
# VerifyNew: the current build must stay alive, show two top-level windows,
# then survive a second launch with that switch still on.
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('ReproduceOld', 'VerifyNew')]
  [string]$Mode,
  [string]$Exe,
  [string]$Screenshot = 'dist/desktop-lyrics-smoke.png'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class DesktopLyricsWindows {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  public static List<string> Titles(uint pid) {
    var found = new List<string>();
    EnumWindows((h, l) => {
      uint owner;
      GetWindowThreadProcessId(h, out owner);
      if (owner == pid && IsWindowVisible(h)) {
        var sb = new StringBuilder(512);
        GetWindowText(h, sb, sb.Capacity);
        if (sb.Length > 0) found.Add(sb.ToString());
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@

function Write-Prefs([string]$Path, [bool]$Enabled) {
  $dir = Split-Path $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $payload = @{ desktopLyrics = $Enabled } | ConvertTo-Json -Compress
  $doc = @{ 'flutter.app_prefs' = $payload }
  [System.IO.File]::WriteAllText($Path, ($doc | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
  Write-Host "prefs $Path <= $payload"
}

function Find-Prefs {
  $roots = @(
    (Join-Path $env:APPDATA 'Flutify\Flutify\shared_preferences.json'),
    (Join-Path $env:APPDATA 'com.flutify.music.flutify_app\shared_preferences.json')
  )
  foreach ($candidate in $roots) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  $found = Get-ChildItem -Path $env:APPDATA -Filter shared_preferences.json -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($found) { return $found.FullName }
  return $roots[0]
}

function Stop-Flutify {
  Get-Process -Name Flutify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
}

function Save-Screen([string]$Path) {
  $dir = Split-Path $Path
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
  Write-Host "screenshot $Path"
}

function Wait-State([System.Diagnostics.Process]$Process, [int]$Seconds, [scriptblock]$Done) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $Process.Refresh()
    if ($Process.HasExited) { return 'exited' }
    if (& $Done) { return 'ready' }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  $Process.Refresh()
  if ($Process.HasExited) { return 'exited' }
  return 'timeout'
}

if ($Mode -eq 'ReproduceOld') {
  Stop-Flutify
  $work = Join-Path $env:RUNNER_TEMP 'flutify-lyrics-old'
  if (Test-Path $work) { Remove-Item -Recurse -Force $work }
  New-Item -ItemType Directory -Path $work | Out-Null
  $zip = Join-Path $work 'old.zip'
  Invoke-WebRequest 'https://github.com/WangJinRrrr/Flutify-lyrics/releases/download/v0.18-lyrics.1/Flutify-v0.18-lyrics.1-windows-x64.zip' -OutFile $zip
  Expand-Archive $zip -DestinationPath (Join-Path $work 'app')
  $oldExe = Get-ChildItem -Path (Join-Path $work 'app') -Filter Flutify.exe -Recurse | Select-Object -First 1
  if (-not $oldExe) { throw 'Old Flutify.exe was not in the v0.18-lyrics.1 zip' }

  $baseline = Start-Process -FilePath $oldExe.FullName -WorkingDirectory $oldExe.DirectoryName -PassThru
  $baselineState = Wait-State $baseline 20 { $false }
  if ($baselineState -eq 'exited') {
    throw "v0.18-lyrics.1 exited before the desktop-lyrics switch was enabled (code $($baseline.ExitCode))"
  }
  Stop-Flutify
  $prefs = Find-Prefs
  Write-Prefs $prefs $true

  $crashing = Start-Process -FilePath $oldExe.FullName -WorkingDirectory $oldExe.DirectoryName -PassThru
  $crashState = Wait-State $crashing 25 { $false }
  if ($crashState -ne 'exited') {
    Stop-Flutify
    throw 'v0.18-lyrics.1 did not crash with desktop lyrics enabled; the reported startup crash was not reproduced'
  }
  Write-Host "reproduced v0.18-lyrics.1 crash, exit code $($crashing.ExitCode)"
  exit 0
}

if (-not $Exe) { throw 'VerifyNew requires -Exe' }
Stop-Flutify
$prefs = Join-Path $env:APPDATA 'Flutify\Flutify\shared_preferences.json'
if (Test-Path $prefs) { Remove-Item -Force $prefs }
$exeItem = Get-Item -LiteralPath $Exe
$first = Start-Process -FilePath $exeItem.FullName -ArgumentList '--desktop-lyrics-smoke' -WorkingDirectory $exeItem.DirectoryName -PassThru
$firstState = Wait-State $first 30 {
  $titles = [DesktopLyricsWindows]::Titles([uint32]$first.Id)
  Write-Host ("windows: " + ($titles -join ' | '))
  $titles.Count -ge 2
}
if ($firstState -eq 'exited') {
  throw "fixed build crashed on first desktop-lyrics launch, exit code $($first.ExitCode)"
}
if ($firstState -ne 'ready') {
  $titles = [DesktopLyricsWindows]::Titles([uint32]$first.Id)
  Stop-Flutify
  throw "fixed build did not show two windows: $($titles -join ' | ')"
}
Save-Screen $Screenshot
Stop-Flutify

$prefs = Find-Prefs
if (-not (Test-Path -LiteralPath $prefs)) { throw "fixed build did not persist preferences at $prefs" }
$saved = Get-Content -Raw -LiteralPath $prefs
if ($saved -notmatch 'desktopLyrics') { throw "preferences do not mention desktopLyrics: $saved" }
Write-Host "persisted $saved"

$second = Start-Process -FilePath $exeItem.FullName -WorkingDirectory $exeItem.DirectoryName -PassThru
$secondState = Wait-State $second 30 {
  $titles = [DesktopLyricsWindows]::Titles([uint32]$second.Id)
  Write-Host ("restart windows: " + ($titles -join ' | '))
  $titles.Count -ge 2
}
if ($secondState -eq 'exited') {
  throw "fixed build crashed on restart with the switch still on, exit code $($second.ExitCode)"
}
if ($secondState -ne 'ready') {
  $titles = [DesktopLyricsWindows]::Titles([uint32]$second.Id)
  Stop-Flutify
  throw "restart did not show two windows: $($titles -join ' | ')"
}
Stop-Flutify
Write-Host 'desktop lyrics smoke passed'
