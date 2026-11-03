# Start test of the Windows client (card « Client Windows : écran gris au
# démarrage », 31 Oct 2026). Used by the CI (x64 runner, ARM64 runner) and
# usable by hand on a PC:
#   powershell -ExecutionPolicy Bypass -File tool\windows_smoke.ps1 -Exe "C:\Program Files\SARCADE\sarcade_app.exe" -Out smoke
# Writes to -Out: report.json (from the app), capture.png (screen after a few
# seconds), demarrage.log (startup log). Exit code 0 when the start window
# showed within one second, the first screen without error, of two launches
# in the same instant one was refused (code 0, logged), a second launch
# during the start was refused leaving one process, and no « Application
# Error » event.
param([Parameter(Mandatory=$true)][string]$Exe, [string]$Out = "smoke", [int]$CaptureAfter = 6, [int]$Timeout = 90)
$ErrorActionPreference = "Continue"
# Full path: [Diagnostics.Process]::Start does not follow Set-Location.
$Exe = (Resolve-Path $Exe).Path
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
$started = Get-Date
$clock = [Diagnostics.Stopwatch]::StartNew()
$exeName = [IO.Path]::GetFileNameWithoutExtension($Exe)
# Two launches in the same instant (card « Windows : SARCADE a cessé de
# fonctionner », lot 25, point 1: the owner's two starts in the same second
# of 2 Nov 2026, one crashed with 0xc0000409 instead of being refused). One
# keeps starting; the other must end by itself with code 0 and write
# « deuxième instance refusée » (second_instance=refused) in demarrage.log.
$a = [Diagnostics.Process]::Start($Exe)
$b = [Diagnostics.Process]::Start($Exe)
$null = $a.Handle; $null = $b.Handle  # keep the exit codes readable
$splashSeen = -1
while ($clock.ElapsedMilliseconds -lt 3000) {
  if ([SplashW32]::Shown($a.Id) -or [SplashW32]::Shown($b.Id)) { $splashSeen = $clock.ElapsedMilliseconds; break }
  Start-Sleep -Milliseconds 10
}
$wait = [Diagnostics.Stopwatch]::StartNew()
while (-not $a.HasExited -and -not $b.HasExited -and $wait.ElapsedMilliseconds -lt 15000) { Start-Sleep -Milliseconds 20 }
$p = $null
if ($a.HasExited -and $b.HasExited) {
  Write-Host "::error title=Windows simultaneous start ($env:PROCESSOR_ARCHITECTURE)::both launches ended (codes 0x$('{0:X8}' -f $a.ExitCode), 0x$('{0:X8}' -f $b.ExitCode)): none kept running"
  $script:simultaneousFailed = $true
  $p = $a
} elseif (-not $a.HasExited -and -not $b.HasExited) {
  Write-Host "::error title=Windows simultaneous start ($env:PROCESSOR_ARCHITECTURE)::neither launch was refused within 15 s"
  Stop-Process -Id $b.Id -Force -ErrorAction SilentlyContinue
  $script:simultaneousFailed = $true
  $p = $a
} else {
  $loser = if ($a.HasExited) { $a } else { $b }
  $p = if ($a.HasExited) { $b } else { $a }
  $code = $loser.ExitCode
  if ($code -eq 0) {
    Write-Host "::notice title=Windows simultaneous start ($env:PROCESSOR_ARCHITECTURE)::pid $($loser.Id) refused in $($wait.ElapsedMilliseconds) ms (exit code 0), pid $($p.Id) kept"
  } else {
    Write-Host "::error title=Windows simultaneous start ($env:PROCESSOR_ARCHITECTURE)::pid $($loser.Id) ended with code 0x$('{0:X8}' -f $code) instead of 0"
    $script:simultaneousFailed = $true
  }
}
# Second launch while the first one starts (card « Windows : pastille de
# liaison grise alors que le Diagnostic dit « Tout fonctionne » », lot 19,
# point 6): the native runner refuses it at once, brings the first window
# to the front and returns; one process must remain.
$p2 = Start-Process -FilePath $Exe -PassThru
$null = $p2.Handle  # keeps the exit code readable
if ($p2.WaitForExit(15000)) {
  Start-Sleep -Milliseconds 300
  $left = @(Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited })
  $code = $p2.ExitCode
  if ($left.Count -eq 1 -and ($null -eq $code -or $code -eq 0)) {
    Write-Host "::notice title=Windows second instance ($env:PROCESSOR_ARCHITECTURE)::second launch refused (exit code $code), one process left"
  } else {
    Write-Host "::error title=Windows second instance ($env:PROCESSOR_ARCHITECTURE)::second launch ended with code $code, $($left.Count) process(es) left instead of 1"
    $script:secondFailed = $true
  }
} else {
  Write-Host "::error title=Windows second instance ($env:PROCESSOR_ARCHITECTURE)::the second launch did not end within 15 s"
  Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue
  $script:secondFailed = $true
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
# No abrupt end (owner's crash: 0xc0000409 in ucrtbase.dll at a second
# launch): no « Application Error » event of the app since the start.
$crashes = @()
try {
  $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; StartTime = $started } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match [regex]::Escape("$exeName.exe") })
} catch { }
if ($crashes.Count -gt 0) {
  foreach ($c in $crashes) { Write-Host "::error title=Windows abrupt end ($env:PROCESSOR_ARCHITECTURE)::$($c.TimeCreated): $(($c.Message -split "`r?`n" | Select-Object -First 6) -join ' | ')" }
  $script:crashed = $true
} else {
  Write-Host "::notice title=Windows abrupt end ($env:PROCESSOR_ARCHITECTURE)::no Application Error event for $exeName.exe"
}
if (Test-Path $log) {
  $m = Select-String -Path $log -Pattern 'second_instance=refused' | Select-Object -Last 1
  if ($m) { Write-Host "::notice title=Windows second instance log ($env:PROCESSOR_ARCHITECTURE)::$($m.Line)" }
  # Two refusals by the native runner (simultaneous launch, then the launch
  # during the start), each written before any DLL of Flutter is loaded.
  $refused = @(Select-String -Path $log -Pattern 'second_instance=refused').Count
  $acquired = @(Select-String -Path $log -Pattern 'single_instance=acquired').Count
  if ($refused -ge 2 -and $acquired -eq 1) {
    Write-Host "::notice title=Windows refusals ($env:PROCESSOR_ARCHITECTURE)::$refused launches refused by the native runner, lock taken once"
  } else {
    Write-Host "::error title=Windows refusals ($env:PROCESSOR_ARCHITECTURE)::$refused native refusal(s) instead of 2, lock taken $acquired time(s) instead of 1"
    $script:simultaneousFailed = $true
  }
} else {
  $script:simultaneousFailed = $true
}
if (-not (Test-Path $report)) { Write-Host "::error title=Windows start::no report: the first screen was not drawn"; exit 1 }
$r = Get-Content $report -Raw | ConvertFrom-Json
Write-Host "--- report.json"; Get-Content $report
if ($script:uniform) { exit 1 }
if ($script:secondFailed) { exit 1 }
if ($script:simultaneousFailed) { exit 1 }
if ($script:crashed) { exit 1 }
if ($script:splashLate) { exit 1 }
if (-not $r.first_frame) { Write-Host "::error title=Windows start::first screen not drawn"; exit 1 }
if ($r.errors.Count -gt 0) {
  foreach ($e in $r.errors) { Write-Host "::error title=Windows start::$($e -replace "`r?`n", ' ')" }
  exit 1
}
Write-Host "::notice title=Windows start ($env:PROCESSOR_ARCHITECTURE)::first screen drawn without error"
Write-Host "First screen drawn without error"
exit 0
