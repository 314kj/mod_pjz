<#
Cookie Optimizer - launch test (TEST ONLY)

What it does:
  Starts Project Zomboid up to 4 times, each time with different environment
  variables set ONLY for the game process, and records whether the Java VM
  picked them up. Nothing in the game folder or ProjectZomboid64.json is edited
  (unless you pass -UseSteamAppIdFile, which creates steam_appid.txt during the
  test and deletes it at the end).

Each time the game opens: wait for the MAIN MENU, then click QUIT.
You do not need to join a server.

Usage (normal PowerShell, no admin needed):
  powershell -ExecutionPolicy Bypass -File .\cookie-launch-test.ps1
  powershell -ExecutionPolicy Bypass -File .\cookie-launch-test.ps1 -GameDir "D:\Steam\steamapps\common\ProjectZomboid"

Result: cookie-test-result.txt next to this script. Send that file back.

Join test (one launch with the agent, you join the server, logs are scanned):
  powershell -ExecutionPolicy Bypass -File .\cookie-launch-test.ps1 -JoinTest
Result: cookie-jointest-result.txt
#>
param(
    [string]$GameDir = "P:\SteamLibrary\steamapps\common\ProjectZomboid",
    [int]$TimeoutMinutes = 15,
    [switch]$UseSteamAppIdFile,
    # -JoinTest: one launch with the agent (heap from JSON), you JOIN the server,
    # then the script scans the logs for anti-cheat / integrity lines.
    [switch]$JoinTest,
    [string]$LogsDir = '',
    # Same as "-cachedir=..." in your Steam launch options, e.g. -CacheDir P:\Zomboid
    [string]$CacheDir = '',
    # Other extra game arguments. Values starting with '-' need the colon form:
    #   -GameArgs:"-someflag"
    [string]$GameArgs = ''
)
if ($CacheDir) { $GameArgs = ("-cachedir=$CacheDir " + $GameArgs).Trim() }
if (-not $LogsDir) { $LogsDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\Logs' }

$ErrorActionPreference = 'Stop'
$here       = $PSScriptRoot
$jar        = Join-Path $here 'cookie-agent-test.jar'
$exe        = Join-Path $GameDir 'ProjectZomboid64.exe'
$jsonPath   = Join-Path $GameDir 'ProjectZomboid64.json'
$jreBin     = Join-Path $GameDir 'jre64\bin'
$resultFile = Join-Path $here 'cookie-test-result.txt'
$script:log = New-Object System.Collections.Generic.List[string]

function Say([string]$s) {
    Write-Host $s
    $script:log.Add($s)
}

function Get-GameProcesses {
    Get-Process -Name ProjectZomboid64 -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($GameDir, [StringComparison]::OrdinalIgnoreCase) }
}

function To-MB([string]$x) {
    if ($x -match '^-Xmx(\d+)([kKmMgG]?)$') {
        $n = [double]$matches[1]
        switch ($matches[2].ToLower()) {
            'g'     { return [int]($n * 1024) }
            'm'     { return [int]$n }
            'k'     { return [int]($n / 1024) }
            default { return [int]($n / 1048576) }
        }
    }
    return $null
}

# ---------- pre-checks ----------
if ($here -match '\s') {
    throw "Move this folder to a path WITHOUT spaces (for example P:\cookie-test). Current: $here"
}
if (-not (Test-Path $jar))  { throw "cookie-agent-test.jar not found next to this script." }
if (-not (Test-Path $exe))  { throw "Game not found: $exe  -> run again with -GameDir `"<your ProjectZomboid folder>`"" }
if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) {
    throw "Start Steam first (logged in), then run this script again."
}
if (Get-GameProcesses) { throw "Close Project Zomboid first, then run this script again." }

# ---------- read ProjectZomboid64.json (read only) ----------
$jsonXmx = $null; $jsonMB = $null; $jsonGc = @(); $leftovers = @()
if (Test-Path $jsonPath) {
    try {
        $cfg = Get-Content $jsonPath -Raw | ConvertFrom-Json
        $vm  = @($cfg.vmArgs)
        $jsonXmx   = $vm | Where-Object { $_ -match '^-Xmx' } | Select-Object -Last 1
        $jsonMB    = To-MB $jsonXmx
        $jsonGc    = @($vm | Where-Object { $_ -match '^-XX:[+-]Use\w*GC$' })
        $leftovers = @($vm + @($cfg.classpath) | Where-Object { $_ -match 'javaagent|agentlib|agentpath|AOTCache|pzopt|zombie_?buddy' })
    } catch {
        Say "Could not parse ProjectZomboid64.json: $($_.Exception.Message)"
    }
} else {
    Say "ProjectZomboid64.json not found at $jsonPath"
}

$testMB = 5000
if ($jsonMB -eq 5000) { $testMB = 6000 }

Say "Cookie launch test  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Say "GameDir: $GameDir"
Say "JSON -Xmx: $jsonXmx ($jsonMB MB)   JSON GC flags: $($jsonGc -join ' ')"
if ($leftovers.Count -gt 0) {
    Say "WARNING: JSON still has agent/optimizer entries: $($leftovers -join ' | ')"
}
Say "Test heap value: $testMB MB (different from JSON on purpose)"

# ---------- one launch ----------
function Run-Test {
    param(
        [string]$Name,
        [string]$Jto,
        [string]$Jo,
        [bool]$PrependPath,
        [string]$Hint,
        [string]$Instruction = 'Wait for the MAIN MENU, then click QUIT.'
    )
    $report  = Join-Path $here "report_$Name.txt"
    $errFile = Join-Path $here "stderr_$Name.txt"
    $outFile = Join-Path $here "stdout_$Name.txt"
    Remove-Item $report, $errFile, $outFile -ErrorAction SilentlyContinue
    $jtoFull = $Jto.Replace('{REPORT}', $report)

    $oldJto  = $env:JAVA_TOOL_OPTIONS
    $oldJo   = $env:_JAVA_OPTIONS
    $oldPath = $env:Path
    $p = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($jtoFull) { $env:JAVA_TOOL_OPTIONS = $jtoFull } else { $env:JAVA_TOOL_OPTIONS = $null }
        if ($Jo)      { $env:_JAVA_OPTIONS = $Jo }          else { $env:_JAVA_OPTIONS = $null }
        if ($PrependPath) { $env:Path = "$jreBin;$oldPath" }

        Say ""
        Say "=== Test $Name : $Hint"
        Say "JAVA_TOOL_OPTIONS = $jtoFull"
        Say "_JAVA_OPTIONS     = $Jo"
        Say "PATH starts with jre64\bin = $PrependPath"
        Write-Host ">>> Game is starting. $Instruction" -ForegroundColor Yellow
        Write-Host ">>> If an error box appears: take a screenshot, then click OK." -ForegroundColor Yellow
        Say "Game arguments    = $GameArgs"
        $sp = @{
            FilePath = $exe; WorkingDirectory = $GameDir; PassThru = $true
            RedirectStandardError = $errFile; RedirectStandardOutput = $outFile
        }
        if ($GameArgs) { $sp.ArgumentList = $GameArgs }
        $p = Start-Process @sp
        $null = $p.Handle   # keep the handle so ExitCode is readable later
    } finally {
        # restore this window's environment right away (the game already has its own copy)
        $env:JAVA_TOOL_OPTIONS = $oldJto
        $env:_JAVA_OPTIONS     = $oldJo
        $env:Path              = $oldPath
    }

    $exited = $p.WaitForExit($TimeoutMinutes * 60 * 1000)
    $sw.Stop()
    if (-not $exited) {
        Say "Timed out after $TimeoutMinutes min with the game still open. Close it; this test counts as unknown."
    }
    Start-Sleep -Seconds 5
    $other = @(Get-GameProcesses | Where-Object { $_.Id -ne $p.Id })

    $r = [ordered]@{
        Name = $Name; Seconds = [int]$sw.Elapsed.TotalSeconds; ExitCode = $null
        Agent = $false; MaxHeapMB = $null; Gc = ''; VmError = $false
        Relaunched = ($other.Count -gt 0)
    }
    try { $r.ExitCode = $p.ExitCode } catch { }

    if (Test-Path $report) {
        $lines = @(Get-Content $report)
        $r.Agent = $true
        $m = $lines | Where-Object { $_ -like 'maxHeapMB=*' } | Select-Object -First 1
        if ($m) { $r.MaxHeapMB = [int]($m.Split('=')[1]) }
        $r.Gc = (@($lines | Where-Object { $_ -like 'gc=*' }) -replace '^gc=', '') -join ', '
        Say "Agent report:"
        foreach ($l in $lines) { Say "  $l" }
    } else {
        Say "Agent report: NOT FOUND (agent did not run)"
    }

    if (Test-Path $errFile) {
        $err = @(Get-Content $errFile -ErrorAction SilentlyContinue | Select-Object -First 60)
        $key = @($err | Where-Object { $_ -match 'Picked up|Error occurred|Could not|instrument|agent|Exception|Error:|Unrecognized|conflict' })
        if ($key.Count -gt 0) {
            Say "stderr (key lines):"
            foreach ($l in $key) { Say "  $l" }
        }
        if ($err -match 'Error occurred during initialization of VM') { $r.VmError = $true }
    }

    if (Test-Path $outFile) {
        $outKey = @(Get-Content $outFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -match 'pzexe: vmArg|set _JAVA_OPTIONS|Error occurred|Could not find|integrity=|agents=|JVM \(free' })
        if ($outKey.Count -gt 0) {
            Say "stdout (key lines):"
            foreach ($l in $outKey) { Say "  $($l.Trim())" }
        }
        if ($outKey -match 'Error occurred during initialization of VM') { $r.VmError = $true }
    }

    Say ("Ran {0}s, exit code {1}, another game window opened by Steam: {2}" -f $r.Seconds, $r.ExitCode, $r.Relaunched)
    if ($r.Relaunched) {
        Say "!! Steam probably restarted the game WITHOUT our settings. Close the game."
        Say "!! Run the script again with:  -UseSteamAppIdFile"
    }
    return [pscustomobject]$r
}

function Heap-Verdict($r) {
    if (-not $r -or -not $r.Agent -or -not $r.MaxHeapMB) { return 'unknown' }
    if ([math]::Abs($r.MaxHeapMB - $testMB) -le ($testMB * 0.05)) { return "YES (heap = $($r.MaxHeapMB) MB = test value)" }
    if ($jsonMB -and [math]::Abs($r.MaxHeapMB - $jsonMB) -le ($jsonMB * 0.05)) { return "NO (heap = $($r.MaxHeapMB) MB = JSON value)" }
    return "unclear (heap = $($r.MaxHeapMB) MB)"
}

# ---------- run ----------
$appIdFile = Join-Path $GameDir 'steam_appid.txt'
$createdAppId = $false
$t1 = $null; $t2 = $null; $t3 = $null; $t4 = $null
try {
    if ($UseSteamAppIdFile -and -not (Test-Path $appIdFile)) {
        Set-Content -Path $appIdFile -Value '108600' -Encoding ASCII
        $createdAppId = $true
        Say "Created $appIdFile for this test (removed at the end)"
    }

    $agentOpt = "-javaagent:$jar={REPORT}"

    if ($JoinTest) {
        $joinStart = Get-Date
        $t5 = Run-Test -Name 'T5' -Jto $agentOpt -Jo '' -PrependPath $true -Hint "agent loaded + join the server (heap from JSON)" `
              -Instruction 'JOIN the server, stay 2-3 minutes (walk around), then quit to desktop.'
        Say ""
        Say "Log lines since $($joinStart.ToString('HH:mm:ss')) in $LogsDir (anti-cheat / integrity / kick):"
        $hits = 0
        $files = @(Get-ChildItem -Path $LogsDir -Recurse -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.LastWriteTime -ge $joinStart })
        foreach ($f in $files) {
            $m = @(Select-String -Path $f.FullName -Pattern 'Anti-cheat|anticheat|integrity|agents=|ValidationFailed|kick' -ErrorAction SilentlyContinue |
                   Select-Object -First 40)
            foreach ($x in $m) { Say ("  {0}: {1}" -f $f.Name, $x.Line.Trim()); $hits++ }
        }
        if ($hits -eq 0) { Say "  (none found in $($files.Count) log files changed since the test started)" }
    } else {

    $t1 = Run-Test -Name 'T1' -Jto "-Xmx${testMB}m $agentOpt" -Jo '' -PrependPath $false `
          -Hint "agent via JAVA_TOOL_OPTIONS, PATH unchanged (also -Xmx${testMB}m there)"

    $needPath = $false
    if (-not $t1.Agent -and -not $t1.Relaunched) {
        $t2 = Run-Test -Name 'T2' -Jto "-Xmx${testMB}m $agentOpt" -Jo '' -PrependPath $true `
              -Hint "same as T1 + jre64\bin first in PATH"
        if ($t2.Agent) { $needPath = $true }
    }

    $agentWorks = $t1.Agent -or ($t2 -and $t2.Agent)
    if ($agentWorks) {
        $t3 = Run-Test -Name 'T3' -Jto $agentOpt -Jo "-Xmx${testMB}m" -PrependPath $needPath `
              -Hint "heap via _JAVA_OPTIONS"
        $t4 = Run-Test -Name 'T4' -Jto $agentOpt -Jo "-XX:-UseZGC -XX:+UseG1GC" -PrependPath $needPath `
              -Hint "switch GC to G1 via _JAVA_OPTIONS"
    } elseif (-not $t1.Relaunched) {
        Say ""
        Say "Agent did not load in T1 or T2 -> T3/T4 skipped. Next step: Process Monitor (see chat)."
    }
    }   # end of normal tests (not -JoinTest)
} finally {
    if ($createdAppId) {
        Remove-Item $appIdFile -ErrorAction SilentlyContinue
        Say "Removed steam_appid.txt"
    }
}

# ---------- summary ----------
if ($JoinTest) {
    $joinFile = Join-Path $here 'cookie-jointest-result.txt'
    $script:log | Set-Content -Path $joinFile -Encoding UTF8
    Write-Host ""
    Write-Host "Saved: $joinFile  -> send this file back." -ForegroundColor Green
    exit
}

$t1or2 = $t1
if (-not $t1.Agent -and $t2) { $t1or2 = $t2 }
$gcText = 'unknown'
if ($t4 -and $t4.Agent)       { $gcText = "game ran, GC = $($t4.Gc)" }
elseif ($t4 -and $t4.VmError) { $gcText = 'VM failed to start' }

Say ""
Say "===== SUMMARY ====="
Say "JSON -Xmx: $jsonXmx ($jsonMB MB) | JSON GC flags: $($jsonGc -join ' ') | test heap: $testMB MB"
Say ("1. Agent loads via JAVA_TOOL_OPTIONS, PATH unchanged: {0}" -f $(if ($t1.Agent) { 'YES' } else { 'NO' }))
if ($t2) { Say ("2. Agent loads with jre64\bin first in PATH:       {0}" -f $(if ($t2.Agent) { 'YES' } else { 'NO' })) }
Say ("3. -Xmx in JAVA_TOOL_OPTIONS beats JSON:           {0}" -f (Heap-Verdict $t1or2))
Say ("4. -Xmx in _JAVA_OPTIONS beats JSON:               {0}" -f (Heap-Verdict $t3))
Say ("5. GC switch via _JAVA_OPTIONS:                    {0}" -f $gcText)

$script:log | Set-Content -Path $resultFile -Encoding UTF8
Write-Host ""
Write-Host "Saved: $resultFile  -> send this file back." -ForegroundColor Green
