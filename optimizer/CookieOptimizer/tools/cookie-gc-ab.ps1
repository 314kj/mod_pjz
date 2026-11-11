<#
Cookie Optimizer - GC A/B test (ZGC vs G1)                        TEST ONLY

What it does
  Starts Project Zomboid once per entry in -Order (default: ZGC, then G1).
  Both runs use the SAME heap (-Xmx from ProjectZomboid64.json unless you pass
  -HeapMB). The only difference between runs is the garbage collector.
  Settings are given ONLY to the game process through _JAVA_OPTIONS:
    - GC choice  (-XX:+UseZGC  or  -XX:-UseZGC -XX:+UseG1GC)
    - Java Flight Recorder (records GC pauses, heap, CPU; ~1-2% overhead)
  No java agent, no file in the game folder or ProjectZomboid64.json is changed.
  It never starts or stops the server.

  While the game runs it samples every few seconds:
    RAM (working set, private working set, private bytes), CPU %,
    GPU memory and GPU 3D % of the game, free RAM of the PC.
  After each run it reads the recording with jre64\bin\jfr.exe and writes a summary.

What YOU do in each run
  1. Wait for the main menu, JOIN the server as usual.
  2. Play the SAME route/scene in every run for about -PlayMinutes (default 15).
     (A beep sounds when the time is up.)
  3. Quit to desktop. The script then starts the next run.

Usage (normal PowerShell window, no admin):
  powershell -ExecutionPolicy Bypass -File .\cookie-gc-ab.ps1 -CacheDir P:\Zomboid
  powershell -ExecutionPolicy Bypass -File .\cookie-gc-ab.ps1 -CacheDir P:\Zomboid -Order ZGC,G1,G1,ZGC
  powershell -ExecutionPolicy Bypass -File .\cookie-gc-ab.ps1 -CacheDir P:\Zomboid -HeapMB 8192

Re-build the summary of an earlier test (no game launch):
  powershell -ExecutionPolicy Bypass -File .\cookie-gc-ab.ps1 -AnalyzeDir P:\Zomboid\Logs\cookie-ab\20261110-1500

Results: <Logs>\cookie-ab\<date-time>\ab-summary.txt (+ .csv, samples, .jfr)
#>
param(
    [string]$GameDir = "P:\SteamLibrary\steamapps\common\ProjectZomboid",
    # Runs in order, comma separated. Allowed: ZGC, G1
    [string]$Order = 'ZGC,G1',
    # 0 = keep -Xmx from ProjectZomboid64.json. Same value for every run. 8192 = what we would tell players.
    [int]$HeapMB = 0,
    [int]$PlayMinutes = 15,
    [int]$SampleSeconds = 5,
    # Same as "-cachedir=..." in your Steam launch options, e.g. -CacheDir P:\Zomboid
    [string]$CacheDir = '',
    # Other extra game arguments. Values starting with '-' need the colon form: -GameArgs:"-x"
    [string]$GameArgs = '',
    [string]$LogsDir = '',
    [string]$OutDir = '',
    # In-game username, used to find the join time in the connections log (optional)
    [string]$Username = '',
    # Optional: full path to PresentMon (Intel, MIT) for real frame times. Asks for admin (UAC).
    [string]$PresentMon = '',
    [switch]$NoGpu,
    [switch]$NoPrompt,
    [int]$TimeoutMinutes = 120,
    [string]$AnalyzeDir = ''
)

$ErrorActionPreference = 'Stop'
$Inv = [Globalization.CultureInfo]::InvariantCulture
if ($CacheDir) { $GameArgs = ("-cachedir=$CacheDir " + $GameArgs).Trim() }
if (-not $LogsDir) {
    if ($CacheDir) { $LogsDir = [IO.Path]::Combine($CacheDir, 'Logs') }
    else { $LogsDir = [IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'Zomboid', 'Logs') }
}
if (-not $OutDir) { $OutDir = [IO.Path]::Combine($LogsDir, 'cookie-ab') }

$exe      = [IO.Path]::Combine($GameDir, 'ProjectZomboid64.exe')
$jsonPath = [IO.Path]::Combine($GameDir, 'ProjectZomboid64.json')
$jfrExe   = [IO.Path]::Combine($GameDir, 'jre64', 'bin', 'jfr.exe')
if (-not (Test-Path $jfrExe)) {
    $alt = [IO.Path]::Combine($GameDir, 'jre64', 'bin', 'jfr')
    if (Test-Path $alt) { $jfrExe = $alt }
}
$script:log = New-Object System.Collections.Generic.List[string]
$script:cimOk = [bool](Get-Command Get-CimInstance -ErrorAction SilentlyContinue)
$script:perfMode = @{}
if ($NoGpu) {
    $script:perfMode['Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory'] = 'off'
    $script:perfMode['Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine'] = 'off'
}

function Say([string]$s) { Write-Host $s; $script:log.Add($s) }
function Rnd($x, [int]$d = 0) { if ($null -eq $x -or $x -eq '') { return '' }; return [math]::Round([double]$x, $d) }
function ToD([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $v = 0.0
    if ([double]::TryParse($s.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, $Inv, [ref]$v)) { return $v }
    return $null
}
function ToDT($x) {
    if ($null -eq $x -or $x -eq '') { return $null }
    if ($x -is [datetime]) { return $x }
    return [datetime]::Parse([string]$x, $Inv, [Globalization.DateTimeStyles]::RoundtripKind)
}
function Pct($arr, [double]$p) {
    $a = @($arr | Where-Object { $null -ne $_ } | Sort-Object)
    if ($a.Count -eq 0) { return $null }
    $i = [int][math]::Ceiling($p / 100.0 * $a.Count) - 1
    if ($i -lt 0) { $i = 0 }
    if ($i -ge $a.Count) { $i = $a.Count - 1 }
    return $a[$i]
}
function Avg($arr) {
    $a = @($arr | Where-Object { $null -ne $_ })
    if ($a.Count -eq 0) { return $null }
    return ($a | Measure-Object -Average).Average
}
function MaxOf($arr) {
    $a = @($arr | Where-Object { $null -ne $_ })
    if ($a.Count -eq 0) { return $null }
    return ($a | Measure-Object -Maximum).Maximum
}
function MinOf($arr) {
    $a = @($arr | Where-Object { $null -ne $_ })
    if ($a.Count -eq 0) { return $null }
    return ($a | Measure-Object -Minimum).Minimum
}
function SumOf($arr) {
    $a = @($arr | Where-Object { $null -ne $_ })
    if ($a.Count -eq 0) { return 0 }
    return ($a | Measure-Object -Sum).Sum
}
function Get-GameProcesses {
    Get-Process -Name ProjectZomboid64 -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($GameDir, [StringComparison]::OrdinalIgnoreCase) }
}
function To-MB([string]$x) {
    if ($x -match '^-Xmx(\d+)([kKmMgG]?)$') {
        $n = [double]$matches[1]
        switch ($matches[2].ToLower()) {
            'g' { return [int]($n * 1024) }
            'm' { return [int]$n }
            'k' { return [int]($n / 1024) }
            default { return [int]($n / 1048576) }
        }
    }
    return $null
}

# ---------------- JFR text parsing ----------------
function Parse-JfrTime([string]$s) {
    if ($s -match '(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d+))?\s*\((\d{4})-(\d{2})-(\d{2})\)') {
        $ms = 0; if ($matches[4]) { $ms = [int](($matches[4] + '000').Substring(0, 3)) }
        return New-Object DateTime ([int]$matches[5]), ([int]$matches[6]), ([int]$matches[7]), ([int]$matches[1]), ([int]$matches[2]), ([int]$matches[3]), $ms
    }
    if ($s -match '(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?') {
        $ms = 0; if ($matches[7]) { $ms = [int](($matches[7] + '000').Substring(0, 3)) }
        return New-Object DateTime ([int]$matches[1]), ([int]$matches[2]), ([int]$matches[3]), ([int]$matches[4]), ([int]$matches[5]), ([int]$matches[6]), $ms
    }
    return $null
}
function Parse-DurMs([string]$s) {
    if ($null -eq $s) { return $null }
    $s = $s.Trim()
    if ($s -eq '' -or $s -like 'N/A*') { return $null }
    $total = 0.0; $found = $false
    foreach ($m in [regex]::Matches($s, '(-?[\d\.,]+)\s*(ns|us|\u00B5s|ms|s|m|h|d)\b')) {
        $v = ToD $m.Groups[1].Value
        if ($null -eq $v) { continue }
        $found = $true
        switch ($m.Groups[2].Value) {
            'ns' { $total += $v / 1e6 }
            'us' { $total += $v / 1e3 }
            'ms' { $total += $v }
            's'  { $total += $v * 1000 }
            'm'  { $total += $v * 60000 }
            'h'  { $total += $v * 3600000 }
            'd'  { $total += $v * 86400000 }
            default { $total += $v / 1e3 }   # micro sign
        }
    }
    if ($found) { return $total }
    return $null
}
function Parse-MemMB([string]$s) {
    if ($s -match '([\d\.,]+)\s*(bytes|byte|B|kB|KB|MB|GB|TB)\b') {
        $v = ToD $matches[1]
        switch -CaseSensitive ($matches[2]) {
            'TB' { return $v * 1048576 }
            'GB' { return $v * 1024 }
            'MB' { return $v }
            'kB' { return $v / 1024 }
            'KB' { return $v / 1024 }
            default { return $v / 1048576 }
        }
    }
    return $null
}
function Parse-Pct([string]$s) {
    if ($s -match '(-?[\d\.,]+)\s*%') { return ToD $matches[1] }
    return $null
}
function Read-JfrEvents([string]$txtFile) {
    # returns a list of hashtables: Type, Time, plus top-level fields as raw strings
    $events = New-Object System.Collections.Generic.List[object]
    $cur = $null
    foreach ($line in [IO.File]::ReadLines($txtFile)) {
        if ($line -match '^(jdk\.\w+) \{\s*$') {
            $cur = @{ Type = $matches[1] }
            continue
        }
        if ($null -eq $cur) { continue }
        if ($line -match '^\}\s*$') {
            if ($cur.ContainsKey('startTime')) { $cur.Time = Parse-JfrTime $cur.startTime }
            $events.Add($cur); $cur = $null
            continue
        }
        if ($line -match '^  (\w+) = (.*)$') { $cur[$matches[1]] = $matches[2].Trim() }
    }
    return $events
}
function Invoke-Jfr([string[]]$JfrArgs, [string]$OutTxt) {
    $errTxt = "$OutTxt.err"
    $a = @('-J-Duser.language=en', '-J-Duser.country=US') + $JfrArgs
    $p = Start-Process -FilePath $jfrExe -ArgumentList $a -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $OutTxt -RedirectStandardError $errTxt
    if ((Test-Path $errTxt) -and (Get-Item $errTxt).Length -eq 0) { Remove-Item $errTxt -ErrorAction SilentlyContinue }
    return $p.ExitCode
}

# ---------------- join time from the connections logs ----------------
function Parse-LogTime([string]$line) {
    if ($line -match '^\[(\d{2})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d{3})\]') {
        return New-Object DateTime (2000 + [int]$matches[3]), ([int]$matches[2]), ([int]$matches[1]), ([int]$matches[4]), ([int]$matches[5]), ([int]$matches[6]), ([int]$matches[7])
    }
    return $null
}
function Read-SharedLines([string]$path) {
    # the server keeps its log files open; read them without locking
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            $sr = New-Object IO.StreamReader($fs)
            while ($null -ne ($l = $sr.ReadLine())) { $lines.Add($l) }
        } finally { $fs.Dispose() }
    } catch { }
    return ,$lines
}
function Find-JoinTime([datetime]$since, [datetime]$until) {
    # join = server "fully-connected" for this player; leave = the next server "disconnect" for the same player
    $files = @(Get-ChildItem -Path $LogsDir -Recurse -File -Filter '*connections*.txt' -ErrorAction SilentlyContinue |
               Where-Object { $_.LastWriteTime -ge $since })
    $joins = New-Object System.Collections.Generic.List[datetime]
    $leaves = New-Object System.Collections.Generic.List[datetime]
    $cJoin = $null; $cLeaves = New-Object System.Collections.Generic.List[datetime]
    foreach ($f in $files) {
        foreach ($line in (Read-SharedLines $f.FullName)) {
            $isMe = $false
            if ($Username) { $isMe = $line -match ('username="' + [regex]::Escape($Username) + '"') }
            else { $isMe = $line -match 'ip="127\.0\.0\.1"' }
            $t = $null
            if ($line -match 'event="fully-connected"' -and $isMe) { $t = Parse-LogTime $line; if ($t) { $joins.Add($t) } }
            elseif ($line -match 'event="disconnect"' -and $isMe) { $t = Parse-LogTime $line; if ($t) { $leaves.Add($t) } }
            elseif ($line -match 'event="connect-state-finish" message="exit"') { $t = Parse-LogTime $line; if ($t -and $t -ge $since -and $t -le $until -and (-not $cJoin -or $t -lt $cJoin)) { $cJoin = $t } }
            elseif ($line -match 'event="force-disconnect"') { $t = Parse-LogTime $line; if ($t) { $cLeaves.Add($t) } }
        }
    }
    $join = $joins | Where-Object { $_ -ge $since -and $_ -le $until } | Sort-Object | Select-Object -First 1
    $how = 'server log (fully-connected)'
    if (-not $join -and $cJoin) { $join = $cJoin.AddSeconds(45); $how = 'client log + 45 s (approx.)' }
    if (-not $join) { return $null }
    $leave = $leaves | Where-Object { $_ -gt $join -and $_ -le $until.AddSeconds(5) } | Sort-Object | Select-Object -First 1
    if (-not $leave) { $leave = $cLeaves | Where-Object { $_ -gt $join -and $_ -le $until.AddSeconds(5) } | Sort-Object | Select-Object -First 1 }
    return @{ Time = $join; How = $how; Leave = $leave }
}

# ---------------- one sample ----------------
function Get-PerfRows([string]$Class, [string]$Wql, [string]$Rx) {
    # WMI performance rows for one process. Falls back to "query all + filter here" if the WQL filter is refused.
    $mode = $script:perfMode[$Class]
    if ($mode -eq 'off') { return @() }
    if ($mode -ne 'all') {
        try { return @(Get-CimInstance -ClassName $Class -Filter $Wql -ErrorAction Stop | Where-Object { $_.Name -match $Rx }) }
        catch { $script:perfMode[$Class] = 'all' }
    }
    try { return @(Get-CimInstance -ClassName $Class -ErrorAction Stop | Where-Object { $_.Name -match $Rx }) }
    catch { $script:perfMode[$Class] = 'off'; return @() }
}
function Get-Sample([int]$procId) {
    $gp = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $gp) { return $null }
    $o = [ordered]@{
        WS = $gp.WorkingSet64 / 1MB; PB = $gp.PrivateMemorySize64 / 1MB
        CpuMs = $gp.TotalProcessorTime.TotalMilliseconds
        PWS = $null; GDed = $null; GShr = $null; G3D = $null; Free = $null
    }
    if (-not $script:cimOk) { return $o }
    if ($script:perfMode['PerfProc'] -ne 'off') {
        try {
            $pp = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$procId" -ErrorAction Stop)
            if ($pp.Count -gt 0) { $o.PWS = [double]$pp[0].WorkingSetPrivate / 1MB }
        } catch { $script:perfMode['PerfProc'] = 'off' }
    }
    try { $o.Free = [double](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1KB } catch { }
    $rx = "^pid_${procId}_"
    $gm = Get-PerfRows 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory' "Name LIKE 'pid[_]$procId[_]%'" $rx
    if ($gm.Count -gt 0) {
        $o.GDed = [double](SumOf ($gm | ForEach-Object { [double]$_.DedicatedUsage })) / 1MB
        $o.GShr = [double](SumOf ($gm | ForEach-Object { [double]$_.SharedUsage })) / 1MB
    }
    $ge = Get-PerfRows 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' "Name LIKE 'pid[_]$procId[_]%engtype[_]3D'" ($rx + '.*engtype_3D$')
    if ($ge.Count -gt 0) { $o.G3D = [double](SumOf ($ge | ForEach-Object { [double]$_.UtilizationPercentage })) }
    return $o
}

# ---------------- statistics for one run ----------------
function Get-RunStats($meta) {
    $runDir = $meta.Dir
    $st = [ordered]@{}
    $st.Run = $meta.Name; $st.GC = $meta.Gc
    $start = ToDT $meta.Start
    $end   = ToDT $meta.End
    $join  = ToDT $meta.Join
    $leave = $null; if ($meta.PSObject.Properties.Name -contains 'Leave') { $leave = ToDT $meta.Leave }
    $wStart = $start; $wEnd = $end; $st.Window = 'whole run (join time not found)'
    if ($join) {
        $endRef = $end; $endTxt = 'game closed'
        if ($leave) { $endRef = $leave; $endTxt = 'left server' }
        $wStart = $join.AddSeconds(30); $wEnd = $endRef.AddSeconds(-10)
        if ($wEnd -le $wStart) { $wStart = $join; $wEnd = $endRef }
        $st.Window = "join+30s .. $endTxt-10s ($($meta.JoinHow))"
    }
    $st.LoadSec = ''; if ($join) { $st.LoadSec = Rnd ($join - $start).TotalSeconds }
    $st.PlayMin = Rnd ($wEnd - $wStart).TotalMinutes 1
    $st.Valid = -not ($meta.Relaunched -or $meta.TimedOut)

    # ---- samples ----
    $rows = @()
    if ($meta.Csv -and (Test-Path $meta.Csv)) { $rows = @(Import-Csv $meta.Csv) }
    $in = @($rows | Where-Object {
        $t = ToDT $_.Time; $t -ge $wStart -and $t -le $wEnd })
    if ($in.Count -eq 0) { $in = $rows }
    $col = { param($name) @($in | ForEach-Object { ToD $_.$name }) }
    $ws = & $col 'WS_MB'; $pb = & $col 'PrivBytes_MB'; $pws = & $col 'PrivWS_MB'
    $cpu = & $col 'CPU_pct'; $gd = & $col 'GPU_Ded_MB'; $gs = & $col 'GPU_Shared_MB'; $g3 = & $col 'GPU_3D_pct'; $fr = & $col 'SysFree_MB'
    $st.Samples = $in.Count
    $st.WS_med = Rnd (Pct $ws 50); $st.WS_p95 = Rnd (Pct $ws 95); $st.WS_max = Rnd (MaxOf $ws)
    $st.PWS_med = Rnd (Pct $pws 50); $st.PWS_max = Rnd (MaxOf $pws)
    $st.PB_med = Rnd (Pct $pb 50); $st.PB_max = Rnd (MaxOf $pb)
    $st.CPU_avg = Rnd (Avg $cpu) 1; $st.CPU_p95 = Rnd (Pct $cpu 95) 1
    $st.GPUded_med = Rnd (Pct $gd 50); $st.GPUded_max = Rnd (MaxOf $gd); $st.GPUshr_med = Rnd (Pct $gs 50)
    $st.GPU3D_avg = Rnd (Avg $g3) 1
    $st.SysFree_min = Rnd (MinOf $fr)

    # ---- JFR ----
    $st.Collector = ''; $st.MaxHeapMB = ''
    $st.GC_count = ''; $st.GC_pause_total_ms = ''; $st.GC_pause_max_ms = ''; $st.GC_pause_p99_ms = ''
    $st.GC_pauses_over_16ms = ''; $st.GC_pauses_over_50ms = ''
    $st.Stall_count = ''; $st.Stall_total_ms = ''; $st.Stall_max_ms = ''; $st.Stall_top_thread = ''
    $st.HeapAfterGC_med = ''; $st.HeapAfterGC_max = ''; $st.JVM_CPU_avg = ''; $st.Machine_CPU_avg = ''
    $st.Jfr = 'missing'
    if ($meta.Jfr -and (Test-Path $meta.Jfr)) {
        if (-not (Test-Path $jfrExe)) {
            $st.Jfr = 'jfr.exe not found (send the .jfr file)'
        } else {
            $txt = Join-Path $runDir "jfr-$($meta.Name).txt"
            if (-not (Test-Path $txt)) {
                $null = Invoke-Jfr @('print', '--stack-depth', '2', '--events',
                    'jdk.GarbageCollection,jdk.ZAllocationStall,jdk.GCHeapSummary,jdk.CPULoad,jdk.GCConfiguration,jdk.GCHeapConfiguration',
                    $meta.Jfr) $txt
            }
            if ((Test-Path $txt) -and (Get-Item $txt).Length -gt 0) {
                $ev = Read-JfrEvents $txt
                $st.Jfr = "ok ($($ev.Count) events)"
                $cfg = $ev | Where-Object { $_.Type -eq 'jdk.GCConfiguration' } | Select-Object -First 1
                if ($cfg) {
                    $st.Collector = ("{0} / {1}" -f $cfg.youngCollector, $cfg.oldCollector).Replace('"', '')
                    $isG1 = $st.Collector -match 'G1'
                    if (($meta.Gc -eq 'G1') -ne $isG1) { $st.Valid = $false; $st.Collector += '  << NOT the GC that was asked' }
                }
                $hc = $ev | Where-Object { $_.Type -eq 'jdk.GCHeapConfiguration' } | Select-Object -First 1
                if ($hc) { $st.MaxHeapMB = Rnd (Parse-MemMB $hc.maxSize) }
                $inW = { param($e) $e.Time -and $e.Time -ge $wStart -and $e.Time -le $wEnd }
                if (@($ev | Where-Object { $_.Time }).Count -eq 0) {
                    $inW = { param($e) $true }
                    $st.Jfr += ' - event times unreadable, numbers are for the whole run'
                }
                $gcs = @($ev | Where-Object { $_.Type -eq 'jdk.GarbageCollection' -and (& $inW $_) })
                $longest = @($gcs | ForEach-Object { Parse-DurMs $_.longestPause })
                $sums    = @($gcs | ForEach-Object { Parse-DurMs $_.sumOfPauses })
                $st.GC_count = $gcs.Count
                $st.GC_pause_total_ms = Rnd (SumOf $sums) 1
                $st.GC_pause_max_ms = Rnd (MaxOf $longest) 2
                $st.GC_pause_p99_ms = Rnd (Pct $longest 99) 2
                $st.GC_pauses_over_16ms = @($longest | Where-Object { $_ -gt 16.7 }).Count
                $st.GC_pauses_over_50ms = @($longest | Where-Object { $_ -gt 50 }).Count
                $stalls = @($ev | Where-Object { $_.Type -eq 'jdk.ZAllocationStall' -and (& $inW $_) })
                $sd = @($stalls | ForEach-Object { Parse-DurMs $_.duration })
                $st.Stall_count = $stalls.Count
                $st.Stall_total_ms = Rnd (SumOf $sd) 1
                $st.Stall_max_ms = Rnd (MaxOf $sd) 2
                if ($stalls.Count -gt 0) {
                    $top = $stalls | Group-Object { ($_.eventThread -replace '\s*\(.*$', '').Replace('"', '') } |
                           Sort-Object Count -Descending | Select-Object -First 2
                    $st.Stall_top_thread = ($top | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join '; '
                }
                $hs = @($ev | Where-Object { $_.Type -eq 'jdk.GCHeapSummary' -and $_.when -match 'After' -and (& $inW $_) } |
                        ForEach-Object { Parse-MemMB $_.heapUsed })
                $st.HeapAfterGC_med = Rnd (Pct $hs 50); $st.HeapAfterGC_max = Rnd (MaxOf $hs)
                $cl = @($ev | Where-Object { $_.Type -eq 'jdk.CPULoad' -and (& $inW $_) })
                $st.JVM_CPU_avg = Rnd (Avg ($cl | ForEach-Object { (Parse-Pct $_.jvmUser) + (Parse-Pct $_.jvmSystem) })) 1
                $st.Machine_CPU_avg = Rnd (Avg ($cl | ForEach-Object { Parse-Pct $_.machineTotal })) 1
            } else {
                $st.Jfr = 'jfr print failed (send the .jfr file)'
            }
        }
    }

    # ---- frames (PresentMon, optional) ----
    $st.FPS_avg = ''; $st.FPS_1pct_low = ''; $st.FrameTime_p99_ms = ''; $st.Hitches_over_50ms = ''; $st.Hitches_over_100ms = ''
    if ($meta.Frames -and (Test-Path $meta.Frames)) {
        try {
            $fr = @(Import-Csv $meta.Frames)
            $ftCol = $null
            foreach ($c in @('FrameTime', 'MsBetweenPresents', 'MsBetweenAppStart')) {
                if ($fr.Count -gt 0 -and ($fr[0].PSObject.Properties.Name -contains $c)) { $ftCol = $c; break }
            }
            if ($ftCol) {
                $ft = @($fr | ForEach-Object { ToD $_.$ftCol } | Where-Object { $null -ne $_ -and $_ -gt 0 })
                # keep frames inside the play window, using elapsed time from the capture start
                $pmStart = $start
                if ($meta.PmStart) { $pmStart = ToDT $meta.PmStart }
                $keep = New-Object System.Collections.Generic.List[double]
                $acc = 0.0
                foreach ($x in $ft) {
                    $acc += $x
                    $t = $pmStart.AddMilliseconds($acc)
                    if ($t -ge $wStart -and $t -le $wEnd) { $keep.Add($x) }
                }
                if ($keep.Count -lt 100) { $keep = $ft }
                $mean = Avg $keep
                if ($mean) { $st.FPS_avg = Rnd (1000.0 / $mean) 1 }
                $p99 = Pct $keep 99
                if ($p99) { $st.FPS_1pct_low = Rnd (1000.0 / $p99) 1; $st.FrameTime_p99_ms = Rnd $p99 1 }
                $st.Hitches_over_50ms = @($keep | Where-Object { $_ -gt 50 }).Count
                $st.Hitches_over_100ms = @($keep | Where-Object { $_ -gt 100 }).Count
            }
        } catch { }
    }
    return $st
}

function Write-Summary([object[]]$metas, [string]$dir) {
    $stats = @()
    foreach ($m in $metas) {
        try { $stats += [pscustomobject](Get-RunStats $m) }
        catch { Say "Could not analyse $($m.Name): $($_.Exception.Message)" }
    }
    if ($stats.Count -eq 0) { Say 'No runs to summarise.'; return }
    $stats | Export-Csv -Path (Join-Path $dir 'ab-summary.csv') -NoTypeInformation -Encoding UTF8

    $rows = @(
        @('Run', 'Run'), @('GC asked', 'GC'), @('Max heap MB (JFR)', 'MaxHeapMB'),
        @('Valid run', 'Valid'), @('Load to join (s)', 'LoadSec'), @('Play window (min)', 'PlayMin'), @('Samples', 'Samples'),
        @('-- RAM of the game --', ''),
        @('Working set median MB', 'WS_med'), @('Working set p95 MB', 'WS_p95'), @('Working set max MB', 'WS_max'),
        @('Private WS median MB (TaskMgr)', 'PWS_med'), @('Private WS max MB', 'PWS_max'),
        @('Private bytes median MB', 'PB_med'), @('Private bytes max MB', 'PB_max'),
        @('PC free RAM min MB', 'SysFree_min'),
        @('-- CPU / GPU --', ''),
        @('Game CPU avg % (whole PC)', 'CPU_avg'), @('Game CPU p95 %', 'CPU_p95'),
        @('JVM CPU avg % (JFR)', 'JVM_CPU_avg'), @('PC CPU avg % (JFR)', 'Machine_CPU_avg'),
        @('GPU dedicated median MB', 'GPUded_med'), @('GPU dedicated max MB', 'GPUded_max'),
        @('GPU shared median MB', 'GPUshr_med'), @('GPU 3D avg %', 'GPU3D_avg'),
        @('-- GC (lower = smoother) --', ''),
        @('GC count', 'GC_count'), @('GC pause total ms', 'GC_pause_total_ms'),
        @('GC pause max ms', 'GC_pause_max_ms'), @('GC pause p99 ms', 'GC_pause_p99_ms'),
        @('GC pauses > 16.7 ms', 'GC_pauses_over_16ms'), @('GC pauses > 50 ms', 'GC_pauses_over_50ms'),
        @('ZGC alloc stalls count', 'Stall_count'), @('ZGC alloc stalls total ms', 'Stall_total_ms'),
        @('ZGC alloc stall max ms', 'Stall_max_ms'), @('Stalled threads (top)', 'Stall_top_thread'),
        @('Heap used after GC median MB', 'HeapAfterGC_med'), @('Heap used after GC max MB', 'HeapAfterGC_max'),
        @('-- Frames (PresentMon, optional) --', ''),
        @('FPS avg', 'FPS_avg'), @('FPS 1% low', 'FPS_1pct_low'), @('Frame time p99 ms', 'FrameTime_p99_ms'),
        @('Frames > 50 ms', 'Hitches_over_50ms'), @('Frames > 100 ms', 'Hitches_over_100ms'),
        @('-- Data --', ''), @('Collector (JFR)', 'Collector'), @('JFR', 'Jfr'), @('Window', 'Window')
    )
    $w0 = 32; $w = 22
    $long = @('Collector', 'Stall_top_thread', 'Jfr', 'Window')
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($r in $rows) {
        if (-not $r[1]) { $out.Add(''); $out.Add($r[0]); continue }
        if ($long -contains $r[1]) {
            $out.Add($r[0] + ':')
            foreach ($s in $stats) { $out.Add(('    {0,-8} {1}' -f $s.Run, [string]$s.($r[1]))) }
            continue
        }
        $line = $r[0].PadRight($w0)
        foreach ($s in $stats) { $line += ([string]$s.($r[1])).PadRight($w) }
        $out.Add($line.TrimEnd())
    }
    $hdr = @(
        "Cookie GC A/B summary  $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "Folder: $dir",
        "Numbers are for the play window (from join + 30 s to leaving the server - 10 s).",
        "Compare runs only when 'Valid run' is True and the route was the same.",
        "RAM: 'Private WS' (= Task Manager) and 'Private bytes' are the fair numbers; working set can count shared pages."
    )
    $sysFile = Join-Path $dir 'sysinfo.txt'
    if (Test-Path $sysFile) { $hdr += @(Get-Content $sysFile) }
    $all = $hdr + @('') + $out
    $all | Set-Content -Path (Join-Path $dir 'ab-summary.txt') -Encoding UTF8
    Write-Host ''
    foreach ($l in $out) { Write-Host $l }
}

# ================= analyse-only mode =================
if ($AnalyzeDir) {
    $metas = @(Get-ChildItem -Path $AnalyzeDir -Filter 'run-*.json' | Sort-Object Name |
               ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json })
    foreach ($m in $metas) { $m.Dir = $AnalyzeDir
        foreach ($k in @('Csv', 'Jfr', 'Frames')) {
            if ($m.$k) { $m.$k = Join-Path $AnalyzeDir (Split-Path $m.$k -Leaf) } }
        # older result files have no leave time: look it up again in the logs if they are still there
        if (-not ($m.PSObject.Properties.Name -contains 'Leave') -or -not $m.Leave) {
            $j = $null
            try { $j = Find-JoinTime (ToDT $m.Start) (ToDT $m.End) } catch { }
            $lv = $null; if ($j -and $j.Leave) { $lv = $j.Leave.ToString('o') }
            $m | Add-Member -NotePropertyName Leave -NotePropertyValue $lv -Force
        }
    }
    Write-Summary $metas $AnalyzeDir
    Write-Host ''
    Write-Host "Saved: $(Join-Path $AnalyzeDir 'ab-summary.txt')" -ForegroundColor Green
    exit
}

# ================= pre-checks =================
$runs = @(($Order -split '[,;\s]+') | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
foreach ($g in $runs) { if ($g -ne 'ZGC' -and $g -ne 'G1') { throw "-Order accepts only ZGC and G1 (got '$g')" } }
if ($runs.Count -eq 0) { throw '-Order is empty' }
if (-not (Test-Path $exe)) { throw "Game not found: $exe  -> run again with -GameDir `"<your ProjectZomboid folder>`"" }
if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Start Steam first (logged in), then run this script again.' }
if ($OutDir -match '[\s,]') { throw "The results folder must not contain spaces or commas: $OutDir  -> use -OutDir P:\cookie-ab" }
if ($PresentMon -and -not (Test-Path $PresentMon)) { throw "PresentMon not found: $PresentMon" }

$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
$runDir = Join-Path $OutDir $stamp
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

# JSON (read only)
$jsonXmx = $null; $jsonMB = $null; $jsonGc = @()
if (Test-Path $jsonPath) {
    try {
        $cfg = Get-Content $jsonPath -Raw | ConvertFrom-Json
        $vm = @($cfg.vmArgs)
        $jsonXmx = $vm | Where-Object { $_ -match '^-Xmx' } | Select-Object -Last 1
        $jsonMB = To-MB $jsonXmx
        $jsonGc = @($vm | Where-Object { $_ -match '^-XX:[+-]Use\w*GC$' })
    } catch { Say "Could not read ProjectZomboid64.json: $($_.Exception.Message)" }
}

# PC info
$sys = New-Object System.Collections.Generic.List[string]
$heapText = "from JSON ($jsonXmx)"; if ($HeapMB -gt 0) { $heapText = "$HeapMB MB (via _JAVA_OPTIONS)" }
$sys.Add("Heap for every run: $heapText | JSON GC flags: $($jsonGc -join ' ')")
$sys.Add("Game args: $GameArgs")
if ($script:cimOk) {
    try { $cs = Get-CimInstance Win32_ComputerSystem; $sys.Add(("PC RAM: {0} MB" -f [math]::Round($cs.TotalPhysicalMemory / 1MB))) } catch { }
    try { $cpuI = @(Get-CimInstance Win32_Processor)[0]; $sys.Add("CPU: $($cpuI.Name.Trim()) ($($cpuI.NumberOfCores) cores / $($cpuI.NumberOfLogicalProcessors) threads)") } catch { }
    try { foreach ($v in @(Get-CimInstance Win32_VideoController)) { $sys.Add("GPU: $($v.Name) driver $($v.DriverVersion)") } } catch { }
    try { $osI = Get-CimInstance Win32_OperatingSystem; $sys.Add("OS: $($osI.Caption) $($osI.Version)") } catch { }
}
try {
    $big = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 6 |
           ForEach-Object { "{0} {1} MB" -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB) }
    $sys.Add("Biggest processes before the test: $($big -join ', ')")
} catch { }
$sys | Set-Content -Path (Join-Path $runDir 'sysinfo.txt') -Encoding UTF8

Say "Cookie GC A/B test  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Say "Runs: $($runs -join ' -> ')   |   play about $PlayMinutes min each   |   results: $runDir"
foreach ($l in $sys) { Say $l }
if (-not (Test-Path $jfrExe)) { Say "NOTE: jfr.exe not found in jre64\bin. Recording still works; the summary will lack GC numbers." }

# ================= one run =================
function Run-One([string]$Gc, [int]$Index) {
    $name = "$Index-$Gc"
    $jfr = Join-Path $runDir "$name.jfr"
    $repo = Join-Path $runDir "jfrrepo-$name"
    $csv = Join-Path $runDir "samples-$name.csv"
    $frames = $null; if ($PresentMon) { $frames = Join-Path $runDir "frames-$name.csv" }
    $outFile = Join-Path $runDir "stdout-$name.txt"
    $errFile = Join-Path $runDir "stderr-$name.txt"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    $jo = @()
    if ($HeapMB -gt 0) { $jo += "-Xmx${HeapMB}m" }
    if ($Gc -eq 'G1') { $jo += '-XX:-UseZGC'; $jo += '-XX:+UseG1GC' } else { $jo += '-XX:+UseZGC' }
    $jo += "-XX:FlightRecorderOptions=repository=$repo,maxchunksize=4m"
    $jo += "-XX:StartFlightRecording=name=cookie,filename=$jfr,settings=default,dumponexit=true"
    $joStr = $jo -join ' '

    while (Get-GameProcesses) {
        Write-Host 'Project Zomboid is still open. Close it; waiting...' -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    Say ''
    Say "=== Run $name  (GC = $Gc) ==="
    Say "_JAVA_OPTIONS = $joStr"
    if (-not $NoPrompt) { $null = Read-Host "Press ENTER to start the game for run $name" }
    Write-Host ">>> Game is starting (GC = $Gc). JOIN the server, play your usual route ~$PlayMinutes min, then QUIT to desktop." -ForegroundColor Yellow
    Write-Host '>>> Keep this window open. Do not change game settings between runs.' -ForegroundColor Yellow

    $oldJto = $env:JAVA_TOOL_OPTIONS; $oldJo = $env:_JAVA_OPTIONS
    $p = $null
    try {
        $env:JAVA_TOOL_OPTIONS = $null
        $env:_JAVA_OPTIONS = $joStr
        $sp = @{ FilePath = $exe; WorkingDirectory = $GameDir; PassThru = $true
                 RedirectStandardError = $errFile; RedirectStandardOutput = $outFile }
        if ($GameArgs) { $sp.ArgumentList = $GameArgs }
        $p = Start-Process @sp
        $null = $p.Handle
    } finally {
        $env:JAVA_TOOL_OPTIONS = $oldJto; $env:_JAVA_OPTIONS = $oldJo
    }
    $t0 = Get-Date

    $pmStart = $null
    if ($PresentMon) {
        try {
            $pmArgs = "--process_name ProjectZomboid64.exe --output_file $frames --terminate_on_proc_exit --stop_existing_session"
            $null = Start-Process -FilePath $PresentMon -ArgumentList $pmArgs -Verb RunAs -WindowStyle Minimized -PassThru
            $pmStart = Get-Date
            Say 'PresentMon started (frame times).'
        } catch { Say "PresentMon did not start: $($_.Exception.Message)" }
    }

    Set-Content -Path $csv -Value 'Time,Sec,WS_MB,PrivWS_MB,PrivBytes_MB,CPU_pct,GPU_Ded_MB,GPU_Shared_MB,GPU_3D_pct,SysFree_MB' -Encoding ASCII
    $cores = [Environment]::ProcessorCount
    $prevCpu = $null; $prevAt = $null; $lastShow = $t0; $beeped = $false; $timedOut = $false
    while ($true) {
        if ($p.WaitForExit($SampleSeconds * 1000)) { break }
        $now = Get-Date
        if (($now - $t0).TotalMinutes -gt $TimeoutMinutes) { $timedOut = $true; Say "Stopped sampling after $TimeoutMinutes min (game still open)."; break }
        $s = Get-Sample $p.Id
        if (-not $s) { continue }
        $cpuPct = $null
        if ($null -ne $prevCpu) {
            $dt = ($now - $prevAt).TotalMilliseconds
            if ($dt -gt 0) { $cpuPct = ($s.CpuMs - $prevCpu) / ($dt * $cores) * 100.0 }
        }
        $prevCpu = $s.CpuMs; $prevAt = $now
        $vals = @($now.ToString('yyyy-MM-ddTHH:mm:ss', $Inv), (Rnd ($now - $t0).TotalSeconds), (Rnd $s.WS), (Rnd $s.PWS), (Rnd $s.PB),
                  (Rnd $cpuPct 1), (Rnd $s.GDed), (Rnd $s.GShr), (Rnd $s.G3D 1), (Rnd $s.Free))
        $line = ($vals | ForEach-Object { [string]$_ }) -join ','
        Add-Content -Path $csv -Value $line -Encoding ASCII
        if (($now - $lastShow).TotalSeconds -ge 60) {
            $lastShow = $now
            Write-Host ("  [{0:mm\:ss}] game RAM {1} MB (private {2} MB), CPU {3}%, PC free RAM {4} MB" -f ($now - $t0), (Rnd $s.WS), (Rnd $s.PB), (Rnd $cpuPct), (Rnd $s.Free))
        }
        if (-not $beeped -and ($now - $t0).TotalMinutes -ge ($PlayMinutes + 2)) {
            $beeped = $true
            Write-Host ">>> About $PlayMinutes min of play done. Quit to desktop when ready." -ForegroundColor Green
            try { [Console]::Beep(880, 300); [Console]::Beep(660, 300) } catch { }
        }
    }
    $tEnd = Get-Date
    Start-Sleep -Seconds 3
    $exitCode = $null; try { $exitCode = $p.ExitCode } catch { }
    $other = @(Get-GameProcesses | Where-Object { $_.Id -ne $p.Id })
    $relaunched = ($other.Count -gt 0 -and ($tEnd - $t0).TotalSeconds -lt 120)
    if ($relaunched) { Say '!! Steam restarted the game WITHOUT our settings. Close the game; this run is not valid.' }

    # JFR file: normal dump on exit, or rebuild it from the repository chunks
    $jfrOk = (Test-Path $jfr) -and ((Get-Item $jfr).Length -gt 4096)
    if (-not $jfrOk -and (Test-Path $jfrExe)) {
        # The game closed without saving the recording: rebuild it from the finished chunks.
        $chunks = @(Get-ChildItem -Path $repo -Recurse -Filter '*.jfr' -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($chunks.Count -gt 0) {
            Say "Recording was not saved at exit; rebuilding it from $($chunks.Count) chunk file(s)..."
            $tries = @(, $chunks)
            if ($chunks.Count -ge 2) { $tries += , @($chunks[0..($chunks.Count - 2)]) }   # without the unfinished last chunk
            foreach ($set in $tries) {
                $tmp = Join-Path $runDir "chunks-$name"
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                foreach ($c in $set) { Copy-Item -LiteralPath $c.FullName -Destination $tmp }
                Remove-Item $jfr -ErrorAction SilentlyContinue
                $null = Invoke-Jfr @('assemble', $tmp, $jfr) (Join-Path $runDir "assemble-$name.txt")
                $chk = Invoke-Jfr @('summary', $jfr) (Join-Path $runDir "check-$name.txt")
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
                if ($chk -eq 0 -and (Test-Path $jfr) -and (Get-Item $jfr).Length -gt 4096) { $jfrOk = $true; break }
            }
            if ($jfrOk) { Say 'Rebuilt OK (the last minute or two may be missing).' }
        }
    }
    if ($jfrOk) {
        Say ("Recording: {0} ({1} MB)" -f (Split-Path $jfr -Leaf), [math]::Round((Get-Item $jfr).Length / 1MB, 1))
        Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue
    } else { Say 'Recording: NOT FOUND or empty (repository kept in the run folder)' }

    if (Test-Path $outFile) {
        $key = @(Get-Content $outFile -ErrorAction SilentlyContinue |
                 Where-Object { $_ -match 'pzexe: vmArg|_JAVA_OPTIONS|Picked up|Error occurred|Could not|Started recording' } | Select-Object -First 30)
        if ($key.Count -gt 0) { Say 'stdout (key lines):'; foreach ($l in $key) { Say "  $($l.Trim())" } }
        if ($key -match 'Error occurred during initialization of VM') { Say '!! The Java VM did not start with these options.' }
    }

    $join = Find-JoinTime $t0 $tEnd
    $joinText = 'not found'; if ($join) { $joinText = "$($join.Time.ToString('HH:mm:ss')) via $($join.How)" }
    Say ("Run {0}: {1:N1} min, exit code {2}, join {3}" -f $name, ($tEnd - $t0).TotalMinutes, $exitCode, $joinText)

    $meta = [ordered]@{
        Name = $name; Gc = $Gc; Dir = $runDir; JavaOptions = $joStr; HeapMB = $HeapMB
        Start = $t0.ToString('o'); End = $tEnd.ToString('o')
        Join = $null; JoinHow = ''; Leave = $null
        Jfr = $jfr; Csv = $csv; Frames = $frames; PmStart = $null
        ExitCode = $exitCode; Relaunched = $relaunched; TimedOut = $timedOut
    }
    if ($join) {
        $meta.Join = $join.Time.ToString('o'); $meta.JoinHow = $join.How
        if ($join.Leave) { $meta.Leave = $join.Leave.ToString('o') }
    }
    if ($pmStart) { $meta.PmStart = $pmStart.ToString('o') }
    $obj = [pscustomobject]$meta
    $obj | ConvertTo-Json | Set-Content -Path (Join-Path $runDir "run-$name.json") -Encoding UTF8
    return $obj
}

# ================= run all =================
$metas = @()
$i = 0
foreach ($g in $runs) {
    $i++
    $metas += Run-One -Gc $g -Index $i
    Write-Summary $metas $runDir
}

$script:log | Set-Content -Path (Join-Path $runDir 'ab-log.txt') -Encoding UTF8
Write-Host ''
Write-Host "Done. Summary: $(Join-Path $runDir 'ab-summary.txt')" -ForegroundColor Green
Write-Host 'Tell Claude the folder name; it can read the results from the Logs folder.' -ForegroundColor Green
