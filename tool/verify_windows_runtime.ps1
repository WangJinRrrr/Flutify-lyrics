param(
  [Parameter(Mandatory = $true)][string]$Directory,
  [Parameter(Mandatory = $true)][string]$BuildDirectory
)
$ErrorActionPreference = 'Stop'

# Use the same native toolchain as CMake, including on Windows ARM64.
$cache = Get-Content -LiteralPath (Join-Path $BuildDirectory 'CMakeCache.txt')
$linkerEntry = @($cache | Where-Object { $_ -match '^CMAKE_LINKER:FILEPATH=' })
if ($linkerEntry.Count -ne 1) { throw 'Cannot locate CMake linker' }
$dumpbin = Join-Path (Split-Path ($linkerEntry[0] -replace '^[^=]+=', '') -Parent) 'dumpbin.exe'
if (!(Test-Path -LiteralPath $dumpbin)) { throw "Cannot locate dumpbin: $dumpbin" }
$binaries = @(Get-ChildItem -LiteralPath $Directory -Recurse -File |
  Where-Object { $_.Extension -in '.exe', '.dll' })
if ($binaries.Count -eq 0) { throw 'No native binaries to inspect' }
$missing = @()
foreach ($binary in $binaries) {
  # /DEPENDENTS includes both normal and delay-load imports.
  $dependencies = & $dumpbin /NOLOGO /DEPENDENTS $binary.FullName
  if ($LASTEXITCODE -ne 0) { throw "Cannot read imports: $($binary.Name)" }
  foreach ($line in $dependencies) {
    $name = $line.Trim()
    if ($name -notmatch '^(vcruntime|msvcp|concrt)140[^\\/\s]*\.dll$') { continue }
    $local = Join-Path $binary.DirectoryName $name
    $root = Join-Path $Directory $name
    if (!(Test-Path -LiteralPath $local) -and !(Test-Path -LiteralPath $root)) {
      $missing += "$($binary.Name) requires missing $name"
    }
  }
}
if ($missing.Count -gt 0) { throw ($missing -join "`n") }
Write-Output "Verified VC runtime dependencies of $($binaries.Count) native binaries."
