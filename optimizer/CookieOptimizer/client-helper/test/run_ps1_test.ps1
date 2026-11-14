# Cookie Slicer - run.ps1 test (Windows PowerShell 5.1, the one Steam's launch option starts).
#   powershell -NoProfile -ExecutionPolicy Bypass -File test\run_ps1_test.ps1 [-Run <run.ps1>] [-Jar <helper jar>]
# Starts run.ps1 the way Steam does (powershell -File run.ps1 <exe> <options...>) with small
# Windows programs in place of the game, and checks the program really started with the
# options whole. Copyright (c) AKA / Cookie Cheetah.
param(
    [string]$Run = (Join-Path $PSScriptRoot '..\setup\run.ps1'),
    [string]$Jar = (Join-Path $PSScriptRoot '..\CookieSlicerHelper.jar')
)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('cs-run-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$noJar = Join-Path $tmp 'no jar'
$withJar = Join-Path $tmp 'with jar'
$game = Join-Path $tmp 'Steam Library\common\Project Zomboid'
New-Item -ItemType Directory -Force $noJar, $withJar, $game | Out-Null
Copy-Item -LiteralPath $Run -Destination (Join-Path $noJar 'run.ps1')
Copy-Item -LiteralPath $Run -Destination (Join-Path $withJar 'run.ps1')
$haveJar = Test-Path -LiteralPath $Jar
if ($haveJar) { Copy-Item -LiteralPath $Jar -Destination (Join-Path $withJar 'CookieSlicerHelper.jar') }
$sys = Join-Path $env:SystemRoot 'System32'
$hostExe = Join-Path $game 'hostname.exe' # a path with spaces, like most Steam libraries
Copy-Item -LiteralPath (Join-Path $sys 'hostname.exe') -Destination $hostExe
$cmdExe = Join-Path $sys 'cmd.exe'
$me = (& (Join-Path $sys 'hostname.exe')).Trim()

$fails = 0
function Check([string]$name, [bool]$ok, [string]$got) {
    if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green }
    else { Write-Host "FAIL  $name`n      got: $got" -ForegroundColor Red; $script:fails++ }
}
# what Steam's launch option does: powershell ... -File "<run.ps1>" %command%
function Start-Like-Steam([string]$dir, [string[]]$command) {
    $env:JAVA_TOOL_OPTIONS = $null; $env:_JAVA_OPTIONS = $null
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'run.ps1') @command 2>&1
    return @{ Out = (($out | ForEach-Object { "$_" }) -join "`n").Trim(); Code = $LASTEXITCODE }
}

try {
    # 1. only the game's exe (a player with no launch options of their own): the case that
    #    started nothing in 1.5.0 - run.ps1 took the first letter of the path as the program
    $r = Start-Like-Steam $noJar @((Join-Path $sys 'hostname.exe'))
    Check 'only the exe: the program starts' ($r.Out -eq $me) $r.Out

    # 2. only the exe, path with spaces
    $r = Start-Like-Steam $noJar @($hostExe)
    Check 'only the exe, path with spaces: the program starts' ($r.Out -eq $me) $r.Out

    # 3. exe + options, "-name:value" kept whole (ZombieBuddy's -agentlib:zbNative)
    $r = Start-Like-Steam $noJar @($cmdExe, '/c', 'echo', '-agentlib:zbNative', '-cachedir=D:\PZ cache')
    Check 'exe + options: options reach the program whole' ($r.Out -match '-agentlib:zbNative' -and $r.Out -match 'cachedir=') $r.Out

    # 4. the game's exit code comes back to Steam
    $r = Start-Like-Steam $noJar @($cmdExe, '/c', 'exit', '7')
    Check 'exit code passed back' ($r.Code -eq 7) ("exit " + $r.Code)

    # 5. helper jar next to run.ps1: the game gets the agent and the RAM savers
    if ($haveJar) {
        $r = Start-Like-Steam $withJar @($cmdExe, '/c', 'echo', 'T=%JAVA_TOOL_OPTIONS%', 'J=%_JAVA_OPTIONS%')
        Check 'jar there: -javaagent ...=client set' ($r.Out -match '-javaagent:.*CookieSlicerHelper\.jar=client') $r.Out
        Check 'jar there: RAM savers set' ($r.Out -match 'UseCompactObjectHeaders') $r.Out
        $r = Start-Like-Steam $withJar @($hostExe)
        Check 'jar there, only the exe: the program starts' ($r.Out -eq $me) $r.Out
    } else {
        Write-Host "SKIP  jar cases (no jar at $Jar)" -ForegroundColor Yellow
    }

    # 6. no jar: no agent
    $r = Start-Like-Steam $noJar @($cmdExe, '/c', 'echo', 'T=%JAVA_TOOL_OPTIONS%')
    Check 'no jar: no -javaagent' ($r.Out -notmatch 'javaagent') $r.Out
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fails -gt 0) { Write-Host "$fails failed" -ForegroundColor Red; exit 1 }
Write-Host 'all passed' -ForegroundColor Green
exit 0
