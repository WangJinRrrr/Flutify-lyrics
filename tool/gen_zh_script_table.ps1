# 生成 lib/services/lyrics/zh_script_table.dart：简繁字形逐字对照表。
#
# 数据来自 Windows 自带的 LCMapStringEx（LCMAP_SIMPLIFIED_CHINESE / LCMAP_TRADITIONAL_CHINESE），
# 与「任务栏歌词」原先在运行时调用的映射完全一致；导出成常量后 Android 等平台也能用。
# 只收录一对一的 BMP 字（转换前后长度不变且字不同）。在 Windows 上运行：
#   powershell -ExecutionPolicy Bypass -File tool/gen_zh_script_table.ps1

$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ZhMap {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern int LCMapStringEx(string locale, uint flags, string src, int srcLen, StringBuilder dst, int dstLen, IntPtr v, IntPtr r, IntPtr s);
    public static string Map(string s, bool toSimplified) {
        var sb = new StringBuilder(s.Length + 8);
        uint flag = toSimplified ? 0x02000000u : 0x04000000u;
        // 输出不带 NUL 结尾，须按返回长度截取
        int n = LCMapStringEx("zh-CN", flag, s, s.Length, sb, sb.Capacity, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        return n > 0 ? sb.ToString(0, n) : s;
    }
    // 逐字映射，只保留一对一的结果：返回 [from, to] 两串，逐字对应
    public static string[] Pairs(bool toSimplified) {
        var from = new StringBuilder(); var to = new StringBuilder();
        int[][] ranges = { new[] { 0x3400, 0x9FFF }, new[] { 0xF900, 0xFAFF } };
        foreach (var r in ranges)
            for (int c = r[0]; c <= r[1]; c++) {
                string s = ((char)c).ToString(), m = Map(s, toSimplified);
                if (m.Length == 1 && m[0] != s[0] && !char.IsSurrogate(m[0])) { from.Append(s); to.Append(m); }
            }
        return new[] { from.ToString(), to.ToString() };
    }
}
'@

$t = [ZhMap]::Pairs($true)
$sp = [ZhMap]::Pairs($false)
$tFrom = $t[0]; $tTo = $t[1]; $sFrom = $sp[0]; $sTo = $sp[1]

function Chunk([string]$text) {
    $lines = @()
    for ($i = 0; $i -lt $text.Length; $i += 100) {
        $lines += "  '" + $text.Substring($i, [Math]::Min(100, $text.Length - $i)) + "'"
    }
    return ($lines -join "`n")
}

$out = @"
// 由 tool/gen_zh_script_table.ps1 生成，请勿手改。
// 数据来源：Windows LCMapStringEx 的简繁字级映射（一对一、BMP 范围）。

/// 繁体专用字（转简体后会变的字），与 [tradToSimpTo] 逐字对应。
const String tradToSimpFrom =
$(Chunk $tFrom);

/// [tradToSimpFrom] 各字对应的简体。
const String tradToSimpTo =
$(Chunk $tTo);

/// 简体专用字（转繁体后会变的字），与 [simpToTradTo] 逐字对应。
const String simpToTradFrom =
$(Chunk $sFrom);

/// [simpToTradFrom] 各字对应的繁体。
const String simpToTradTo =
$(Chunk $sTo);

"@
$path = Join-Path $PSScriptRoot '..\lib\services\lyrics\zh_script_table.dart'
New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
[IO.File]::WriteAllText((Resolve-Path (Split-Path $path)).Path + '\zh_script_table.dart', ($out -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
"trad->simp: $($tFrom.Length)  simp->trad: $($sFrom.Length)"
