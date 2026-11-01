# Start test of the Windows client (card « Client Windows : écran gris au
# démarrage », 31 Oct 2026). Used by the CI (x64 runner, ARM64 runner) and
# usable by hand on a PC:
#   powershell -ExecutionPolicy Bypass -File tool\windows_smoke.ps1 -Exe "C:\Program Files\SARCADE\sarcade_app.exe" -Out smoke
# Writes to -Out: report.json (from the app), capture.png (screen after a few
# seconds), demarrage.log (startup log). Exit code 0 when the start window
# showed within one second and the first screen without error.
param([Parameter(Mandatory=$true)][string]$Exe, [string]$Out = "smoke", [int]$CaptureAfter = 6, [int]$Timeout = 90)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$report = Join-Path $Out "report.json"
Remove-Item $report -ErrorAction SilentlyContinue
$env:SARCADE_SMOKE_FILE = $report
Write-Host "Architecture: $env:PROCESSOR_ARCHITECTURE ; exe: $Exe"
# Fresh log: the unit tests of the same machine write to it too.
$log = Join-Path $env:LOCALAPPDATA "SARCADE\logs\demarrage.log"
Remove-Item $log -ErrorAction SilentlyContinue
# Start window (card « Windows : logo SARCADE affiché dès le clic sur
# l'icône », 1 Nov 2026): it must show in less than one second. Looked for
# by its class while the app starts; the app also writes the time it took
# (splash_ms, from the creation of the process) in demarrage.log.
# Top-level windows of the process enumerated (as for its main window):
# FindWindow did not see them on the CI machine.
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class SplashW32 {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  public static bool Shown(int pid) {
    bool found = false;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint owner; GetWindowThreadProcessId(h, out owner);
      if (owner != (uint)pid || !IsWindowVisible(h)) return true;
      StringBuilder name = new StringBuilder(64); GetClassName(h, name, 64);
      if (name.ToString() == "SARCADE_SPLASH") { found = true; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  } }
"@
$clock = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $Exe -PassThru
$splashSeen = -1
while ($clock.ElapsedMilliseconds -lt 3000) {
  if ([SplashW32]::Shown($p.Id)) { $splashSeen = $clock.ElapsedMilliseconds; break }
  Start-Sleep -Milliseconds 10
}
Start-Sleep -Milliseconds ([Math]::Max(0, $CaptureAfter * 1000 - $clock.ElapsedMilliseconds))
try {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $Out "capture.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  Write-Host "Capture saved"
  # Grey window check (the owner's symptom): colours inside the window of
  # the app. A uniform window means the engine drew nothing, even when the
  # Dart code reports its first screen.
  try {
  Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W32 { [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t); }
"@
  $p.Refresh(); $h = $p.MainWindowHandle
  # The Flutter window is not always the « main window » of the process:
  # found by its title too (« SARCADE », older builds « sarcade_app »).
  if ($h -eq [IntPtr]::Zero) { $h = [W32]::FindWindow($null, "SARCADE") }
  if ($h -eq [IntPtr]::Zero) { $h = [W32]::FindWindow($null, "sarcade_app") }
  if ($h -ne [IntPtr]::Zero) {
    $r = New-Object W32+R; [void][W32]::GetWindowRect($h, [ref]$r)
    $colors = @{}
    for ($x = [Math]::Max($r.L + 8, $b.Left); $x -lt [Math]::Min($r.Rt - 8, $b.Right); $x += 12) {
      for ($y = [Math]::Max($r.T + 40, $b.Top); $y -lt [Math]::Min($r.B - 8, $b.Bottom); $y += 12) {
        $colors[$bmp.GetPixel($x - $b.Left, $y - $b.Top).ToArgb()] = 1 } }
    $n = $colors.Count
    Write-Host "::notice title=Windows window ($env:PROCESSOR_ARCHITECTURE)::$($r.Rt - $r.L)x$($r.B - $r.T), $n distinct colours"
    if ($n -lt 4) { Write-Host "::error title=Windows window::uniform window ($n colours): nothing drawn (grey screen)"; $script:uniform = $true }
  } else { Write-Host "::warning title=Windows window::no main window found" }
  } catch { Write-Host "::warning title=Windows window::check failed: $($_.Exception.Message -replace "`r?`n", ' ')" }
} catch { Write-Host "::warning title=Windows capture::no capture: $($_.Exception.Message -replace "`r?`n", ' ')" }
if (-not $p.WaitForExit($Timeout * 1000)) {
  Write-Host "::error title=Windows start::the app did not end within $Timeout s (first screen never drawn?)"
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
$splashMs = -1; $firstMs = -1
if (Test-Path $log) {
  $m = Select-String -Path $log -Pattern 'splash_ms=(\d+)' | Select-Object -Last 1
  if ($m) { $splashMs = [int]$m.Matches[0].Groups[1].Value }
  $m = Select-String -Path $log -Pattern 'first_frame_ms=(\d+)' | Select-Object -Last 1
  if ($m) { $firstMs = [int]$m.Matches[0].Groups[1].Value }
}
$arch = $env:PROCESSOR_ARCHITECTURE
$seenText = if ($splashSeen -ge 0) { "seen by the test after $splashSeen ms" } else { "not seen by the test within 3 s" }
$logText = if ($splashMs -ge 0) { "shown $splashMs ms after the creation of the process" } else { "no time in the log" }
$firstText = if ($firstMs -ge 0) { "first image of Flutter after $firstMs ms" } else { "first image of Flutter: no time in the log" }
# The window may close before the test sees it (fast start): the time
# written by the app is then the measure.
if (($splashSeen -ge 0 -and $splashSeen -le 1000) -or ($splashMs -ge 0 -and $splashMs -le 1000)) {
  Write-Host "::notice title=Windows start window ($arch)::$seenText, $logText; $firstText"
} else {
  Write-Host "::error title=Windows start window ($arch)::not shown within 1 s: $seenText, $logText; $firstText"
  $script:splashLate = $true
}
if (Test-Path $log) {
  Copy-Item $log (Join-Path $Out "demarrage.log"); Write-Host "--- demarrage.log"; Get-Content $log -Tail 80
  # Readable from the API without downloading the artifact (one annotation).
  $tail = (Get-Content $log | Select-Object -Last 12) -join " | "
  Write-Host "::notice title=Windows start log ($env:PROCESSOR_ARCHITECTURE)::$tail"
}
else { Write-Host "::warning title=Windows start::no startup log (Dart code never ran?)" }
if (-not (Test-Path $report)) { Write-Host "::error title=Windows start::no report: the first screen was not drawn"; exit 1 }
$r = Get-Content $report -Raw | ConvertFrom-Json
Write-Host "--- report.json"; Get-Content $report
if ($script:uniform) { exit 1 }
if ($script:splashLate) { exit 1 }
if (-not $r.first_frame) { Write-Host "::error title=Windows start::first screen not drawn"; exit 1 }
if ($r.errors.Count -gt 0) {
  foreach ($e in $r.errors) { Write-Host "::error title=Windows start::$($e -replace "`r?`n", ' ')" }
  exit 1
}
Write-Host "::notice title=Windows start ($env:PROCESSOR_ARCHITECTURE)::first screen drawn without error"
Write-Host "First screen drawn without error"
exit 0
