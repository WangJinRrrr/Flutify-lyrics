# Capture the Flutify window to a PNG (for UI checks).
Add-Type -AssemblyName System.Drawing
$src = @'
using System;
using System.Runtime.InteropServices;
public class U32 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies System.Drawing
$p = Get-Process flutify_app
[U32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 600
$r = New-Object U32+RECT
[U32]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
"rect: $($r.Left),$($r.Top) ${w}x${h}"
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$out = "C:\Users\ZhaoYunFeng\.cursor\projects\d-Flutify\assets\flutify_home_check.png"
$bmp.Save($out)
$g.Dispose(); $bmp.Dispose()
"saved: $out"
