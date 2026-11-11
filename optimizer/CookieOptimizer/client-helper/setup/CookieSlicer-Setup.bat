<# : batch portion (PowerShell reads this block as a comment)
@echo off
title Cookie Slicer Helper - Setup
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:CS_SELF='%~f0'; Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
echo.
pause
goto :eof
#>
# Cookie Slicer Helper - Setup (Windows). Copyright (c) AKA / Cookie Cheetah.
# [1] Install / update - one press, nothing else to do:
#     - copies CookieSlicerHelper.jar + run.ps1 (they come with the Cookie Slicer mod
#       Steam downloads) to %LOCALAPPDATA%\CookieSlicer
#     - game RAM: when the game gets less than fits this PC (half its RAM, 4-16 GB,
#       at least 4 GB left), sets that for the next start (heap.txt, read by run.ps1)
#     - sets the game's Steam launch option to start through run.ps1 (your own options
#       stay after it). Steam must be closed for that: it closes and opens again by itself.
#     - turns the Cookie Slicer mod on for the MAIN MENU (Zomboid\mods\default.txt), so
#       its button is there before joining (on a server the server's mod list counts)
#     - checks the game's start settings (ProjectZomboid64.json in the game folder) and
#       repairs what stops the game from starting or joining: PZ Optimization left in it
#       (its jar / AOT cache break after every game update) and game RAM that does not fit
#       this PC. The file as it was is kept as ProjectZomboid64.json.cookieslicer-backup.
# [2] Uninstall - removes the helper, our part of the launch option and the main-menu line;
#     ProjectZomboid64.json goes back to the backup if only its RAM was changed (PZ
#     Optimization leftovers are not put back: they stop the game).
# [3] Check.
# Only ProjectZomboid64.json is changed (backup first). It never starts or closes the game.
# Log: %TEMP%\CookieSlicer-setup.log

$ErrorActionPreference = 'Stop'
$AppDir = Join-Path $env:LOCALAPPDATA 'CookieSlicer'
$JarName = 'CookieSlicerHelper.jar'
$Log = Join-Path $env:TEMP 'CookieSlicer-setup.log'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Say([string]$t, [string]$c = 'Gray') {
    Write-Host $t -ForegroundColor $c
    try { [System.IO.File]::AppendAllText($Log, (Get-Date -Format 'HH:mm:ss') + ' ' + $t + "`r`n", $Utf8) } catch { }
}

function Get-SteamInfo {
    $roots = @(); $exe = $null
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = Get-ItemProperty -Path $k -ErrorAction Stop
            if ($p.SteamPath) { $roots += ($p.SteamPath -replace '/', '\') }
            if ($p.InstallPath) { $roots += ($p.InstallPath -replace '/', '\') }
            if ($p.SteamExe -and -not $exe) { $exe = ($p.SteamExe -replace '/', '\') }
        } catch { }
    }
    $roots = @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    if (-not $exe -and $roots.Count -gt 0) { $exe = Join-Path $roots[0] 'steam.exe' }
    return @{ Roots = $roots; Exe = $exe }
}

function Get-SteamLibraries($roots) {
    $libs = @()
    foreach ($r in $roots) {
        $libs += $r
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    return @($libs | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

function Find-Jar($libs, $cacheDirs) {
    $c = @()
    if ($env:CS_SELF) { $c += (Join-Path (Split-Path -Parent $env:CS_SELF) $JarName) }
    foreach ($l in $libs) {
        $ws = Join-Path $l 'steamapps\workshop\content\108600'
        if (Test-Path -LiteralPath $ws) {
            foreach ($d in Get-ChildItem -LiteralPath $ws -Directory) {
                $c += (Join-Path $d.FullName "mods\CookieSlicer\42\helper\$JarName")
            }
        }
    }
    foreach ($z in @((Join-Path $env:USERPROFILE 'Zomboid')) + $cacheDirs) {
        if ($z) { $c += (Join-Path $z "Workshop\CookieSlicer\Contents\mods\CookieSlicer\42\helper\$JarName") }
    }
    $have = @($c | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Item -LiteralPath $_ })
    if ($have.Count -eq 0) { return $null }
    return ($have | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Get-LocalConfig($roots) {
    $files = @()
    foreach ($r in $roots) {
        $ud = Join-Path $r 'userdata'
        if (-not (Test-Path -LiteralPath $ud)) { continue }
        foreach ($d in Get-ChildItem -LiteralPath $ud -Directory) {
            $f = Join-Path $d.FullName 'config\localconfig.vdf'
            if (Test-Path -LiteralPath $f) { $files += (Get-Item -LiteralPath $f) }
        }
    }
    if ($files.Count -eq 0) { return $null }
    return ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# The "108600" { ... } block of localconfig.vdf: body start/end, the LaunchOptions value
# span if there is one, and the indent to use. $null when the game has no block.
function Find-AppBlock([string]$text) {
    foreach ($m in [regex]::Matches($text, '"108600"\s*\{')) {
        $start = $m.Index + $m.Length
        $depth = 1; $k = $start; $inStr = $false
        while ($k -lt $text.Length -and $depth -gt 0) {
            $ch = $text[$k]
            if ($inStr) { if ($ch -eq '\') { $k++ } elseif ($ch -eq '"') { $inStr = $false } }
            elseif ($ch -eq '"') { $inStr = $true }
            elseif ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') { $depth-- }
            $k++
        }
        $end = $k - 1
        $body = $text.Substring($start, $end - $start)
        $lineStart = $text.LastIndexOf("`n", $m.Index) + 1
        $indent = [regex]::Match($text.Substring($lineStart, $m.Index - $lineStart), '^[\t ]*').Value + "`t"
        $lo = [regex]::Match($body, '(?m)^\s*"LaunchOptions"\s*"((?:[^"\\]|\\.)*)"')
        $r = @{ Start = $start; End = $end; Indent = $indent; Value = $null; VStart = -1; VLen = 0 }
        if ($lo.Success) {
            $r.Value = (($lo.Groups[1].Value -replace '\\"', '"') -replace '\\\\', '\')
            $r.VStart = $start + $lo.Groups[1].Index
            $r.VLen = $lo.Groups[1].Length
        }
        return $r
    }
    return $null
}

function Get-LaunchOptions($cfg) {
    if (-not $cfg) { return $null }
    $b = Find-AppBlock ([System.IO.File]::ReadAllText($cfg))
    if (-not $b) { return '' }
    if ($null -eq $b.Value) { return '' }
    return $b.Value
}

# writes the game's launch options into localconfig.vdf (Steam must be closed)
function Set-LaunchOptions([string]$cfg, [string]$value) {
    $text = [System.IO.File]::ReadAllText($cfg)
    $b = Find-AppBlock $text
    if (-not $b) { throw 'Project Zomboid was not found in Steam settings (play it once first)' }
    $esc = $value.Replace('\', '\\').Replace('"', '\"')
    if ($b.VStart -ge 0) {
        $new = $text.Substring(0, $b.VStart) + $esc + $text.Substring($b.VStart + $b.VLen)
    } else {
        $nl = "`n"; if ($text.Contains("`r`n")) { $nl = "`r`n" }
        $new = $text.Substring(0, $b.Start) + $nl + $b.Indent + '"LaunchOptions"' + "`t`t" + '"' + $esc + '"' + $text.Substring($b.Start)
    }
    $backup = "$cfg.cookieslicer-backup"
    if (-not (Test-Path -LiteralPath $backup)) { [System.IO.File]::WriteAllText($backup, $text, $Utf8) }
    [System.IO.File]::WriteAllText($cfg, $new, $Utf8)
    if ((Get-LaunchOptions $cfg) -ne $value) {
        [System.IO.File]::WriteAllText($cfg, $text, $Utf8)
        throw 'could not write the Steam launch option (nothing changed)'
    }
}

# Cookie Slicer on/off for the main menu: Zomboid\mods\default.txt ("mod = CookieSlicer,")
function Set-MenuMod([string]$zomboid, [bool]$on) {
    $f = Join-Path $zomboid 'mods\default.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    $text = [System.IO.File]::ReadAllText($f)
    $nl = "`n"; if ($text.Contains("`r`n")) { $nl = "`r`n" }
    $has = $text -match '(?m)^\s*mod\s*=\s*\\?CookieSlicer\s*,'
    if ($on -and -not $has) {
        $m = [regex]::Match($text, '(?ms)^mods\s*\{.*?^\}')
        if (-not $m.Success) { return $false }
        $close = $m.Index + $m.Length - 1
        $text = $text.Substring(0, $close) + '    mod = CookieSlicer,' + $nl + $text.Substring($close)
    } elseif (-not $on -and $has) {
        $text = [regex]::Replace($text, '(?m)^\s*mod\s*=\s*\\?CookieSlicer\s*,\s*\r?\n', '')
    } else { return $true }
    [System.IO.File]::WriteAllText($f, $text, $Utf8)
    return $true
}

# options without our start script part ("... run.ps1" %command%)
function Strip-Ours([string]$o) {
    if (-not $o) { return '' }
    $i = $o.IndexOf('%command%', [StringComparison]::OrdinalIgnoreCase)
    if ($i -ge 0 -and $o.Substring(0, $i) -match 'CookieSlicer') { return $o.Substring($i + 9).Trim() }
    return $o.Trim()
}

function Close-Steam {
    $p = @(Get-Process -Name 'steam' -ErrorAction SilentlyContinue)
    if ($p.Count -eq 0) { return $false }
    Say 'Steam closes for a moment and opens again by itself...' Yellow
    Start-Process 'steam://exit'
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 1
        if (@(Get-Process -Name 'steam' -ErrorAction SilentlyContinue).Count -eq 0) { Start-Sleep -Seconds 2; return $true }
    }
    throw 'Steam did not close (a download running?). Close Steam yourself, then run this again.'
}

# Game RAM (same rule as the helper, 1.2.1): what the game used at most in the last
# sessions (heapstats.txt, written by the helper) x 1.5 + 1.5 GB, at least 6 GB; 8 GB
# before there is any data. Safe = the most this PC can spare: 6 GB left for the rest on
# PCs with 16 GB or more (at most 16 GB for the game), 4 GB left on smaller ones, >= 3 GB.
function Get-RamPlan([double]$total, [double]$peak) {
    if ($total -ge 16384) { $safe = [math]::Min(16384, [math]::Floor(($total - 6144) / 1024) * 1024) }
    else { $safe = [math]::Max(3072, [math]::Floor(($total - 4096) / 1024) * 1024) }
    if ($peak -gt 0) { $need = [math]::Max(6144, [math]::Ceiling(($peak * 1.5 + 1536) / 1024) * 1024) } else { $need = 8192 }
    $rec = [math]::Max(3072, [math]::Min($safe, $need))
    return @{ Total = [int]$total; Rec = [int]$rec; Safe = [int]$safe }
}

function Get-RecommendMB {
    $total = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
    $peak = 0
    $sf = Join-Path $AppDir 'heapstats.txt'
    if (Test-Path -LiteralPath $sf) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($sf), 'peaks=([\d,]+)')
        if ($m.Success) { foreach ($x in $m.Groups[1].Value.Split(',')) { if ($x -and [int]$x -gt $peak) { $peak = [int]$x } } }
    }
    return Get-RamPlan $total $peak
}

# -Xmx the game starts with now (MB): heap.txt, else the game's own json, else 3072
function Get-CurrentHeapMB($libs) {
    $hf = Join-Path $AppDir 'heap.txt'
    if (Test-Path -LiteralPath $hf) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($hf), 'heap_mb=(\d+)')
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    foreach ($l in $libs) {
        $j = Join-Path $l 'steamapps\common\ProjectZomboid\ProjectZomboid64.json'
        if (Test-Path -LiteralPath $j) {
            $m = [regex]::Match([System.IO.File]::ReadAllText($j), '"-Xmx(\d+)([kKmMgG]?)"')
            if ($m.Success) {
                $v = [double]$m.Groups[1].Value
                switch ($m.Groups[2].Value.ToLower()) { 'g' { $v *= 1024 } 'k' { $v /= 1024 } '' { $v /= 1MB } }
                return [int]$v
            }
        }
    }
    return 3072
}

# ---------------------------------------------------------------- ProjectZomboid64.json

function Find-GameJson($libs) {
    foreach ($l in $libs) {
        $j = Join-Path $l 'steamapps\common\ProjectZomboid\ProjectZomboid64.json'
        if (Test-Path -LiteralPath $j) { return $j }
    }
    return $null
}

$BadArg = '(?i)AOTCache|SharedArchiveFile|AOTMode|pzopt'

# what the file holds: Issues (broken, pzopt, aot), XmxMB, other Java agents
function Read-GameJson([string]$path) {
    $text = [System.IO.File]::ReadAllText($path)
    $r = @{ Text = $text; Obj = $null; Issues = @(); XmxMB = 0; Agents = @() }
    try { $r.Obj = $text | ConvertFrom-Json } catch { $r.Issues += 'broken'; return $r }
    if (-not $r.Obj.mainClass -or -not $r.Obj.classpath -or -not $r.Obj.vmArgs) { $r.Issues += 'broken'; return $r }
    if (@($r.Obj.classpath | Where-Object { $_ -match 'pzopt' }).Count -gt 0) { $r.Issues += 'pzopt' }
    $all = @($r.Obj.vmArgs)
    if ($r.Obj.windows) { foreach ($p in $r.Obj.windows.PSObject.Properties) { if ($p.Value.vmArgs) { $all += @($p.Value.vmArgs) } } }
    if (@($all | Where-Object { $_ -match $BadArg }).Count -gt 0) { $r.Issues += 'aot' }
    foreach ($a in $all) {
        if ($a -match '^-javaagent:(.+)$' -and $a -notmatch 'CookieSlicer') { $r.Agents += (Split-Path -Leaf ($Matches[1].Trim('"'))) }
    }
    foreach ($a in @($r.Obj.vmArgs)) {
        $m = [regex]::Match($a, '^-Xmx(\d+)([kKmMgG]?)$')
        if ($m.Success) {
            $v = [double]$m.Groups[1].Value
            switch ($m.Groups[2].Value.ToLower()) { 'g' { $v *= 1024 } 'k' { $v /= 1024 } '' { $v /= 1MB } }
            $r.XmxMB = [int]$v
        }
    }
    return $r
}

# JSON in the game's own layout (tabs, one value per line); works in Windows PowerShell 5.1
function ConvertTo-GameJson($v, [string]$ind) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [string]) { return '"' + $v.Replace('\', '\\').Replace('"', '\"') + '"' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [ValueType]) { return ([System.Convert]::ToString($v, [System.Globalization.CultureInfo]::InvariantCulture)) }
    $in = $ind + "`t"
    if ($v -is [System.Collections.IEnumerable]) {
        $items = @(); foreach ($x in $v) { $items += ($in + (ConvertTo-GameJson $x $in)) }
        if ($items.Count -eq 0) { return '[]' }
        return "[`n" + ($items -join ",`n") + "`n" + $ind + ']'
    }
    $props = @(); foreach ($p in $v.PSObject.Properties) { $props += ($in + '"' + $p.Name + '": ' + (ConvertTo-GameJson $p.Value $in)) }
    if ($props.Count -eq 0) { return '{}' }
    return "{`n" + ($props -join ",`n") + "`n" + $ind + '}'
}

# removes PZ Optimization leftovers, sets -Xmx when it does not fit this PC; backup first.
# Returns what was changed (empty = nothing to do).
function Repair-GameJson([string]$path, $info, [int]$wantMB, [int]$totalMB) {
    $o = $info.Obj; $changes = @()
    $cp = @($o.classpath | Where-Object { $_ -notmatch 'pzopt' })
    if ($cp.Count -ne @($o.classpath).Count) { $o.classpath = $cp; $changes += 'pzopt' }
    $va = @($o.vmArgs | Where-Object { $_ -notmatch $BadArg })
    if ($va.Count -ne @($o.vmArgs).Count) { $changes += 'aot' }
    if ($o.windows) {
        foreach ($p in $o.windows.PSObject.Properties) {
            if ($p.Value.vmArgs) {
                $w = @($p.Value.vmArgs | Where-Object { $_ -notmatch $BadArg })
                if ($w.Count -ne @($p.Value.vmArgs).Count) { $p.Value.vmArgs = $w; if ($changes -notcontains 'aot') { $changes += 'aot' } }
            }
        }
    }
    $cur = $info.XmxMB
    if ($wantMB -gt 0 -and ($cur -lt $wantMB -or $cur -gt ($totalMB - 2048))) {
        $x = '-Xmx' + $wantMB + 'm'
        $i = -1; for ($k = 0; $k -lt $va.Count; $k++) { if ($va[$k] -match '^-Xmx') { $i = $k } }
        if ($i -ge 0) { $va[$i] = $x } else { $va += $x }
        $changes += 'xmx'
    }
    if ($changes.Count -eq 0) { return @() }
    $o.vmArgs = $va
    $backup = "$path.cookieslicer-backup"
    if (-not (Test-Path -LiteralPath $backup)) { [System.IO.File]::WriteAllText($backup, $info.Text, $Utf8) }
    $new = (ConvertTo-GameJson $o '') + "`n"
    if ($info.Text -match "`r`n") { $new = $new.Replace("`n", "`r`n") } # keep the file's own line ends
    [System.IO.File]::WriteAllText($path, $new, $Utf8)
    try { $null = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json }
    catch { [System.IO.File]::WriteAllText($path, $info.Text, $Utf8); throw 'could not repair ProjectZomboid64.json (left as it was)' }
    # what was changed since the backup (all runs together): uninstall puts the backup
    # back only when that was nothing but the RAM
    $jc = Join-Path $AppDir 'json-changes.txt'
    $all = @($changes)
    if (Test-Path -LiteralPath $jc) {
        $prev = [regex]::Match([System.IO.File]::ReadAllText($jc), 'changes=([a-z,]+)')
        if ($prev.Success) { foreach ($x in $prev.Groups[1].Value.Split(',')) { if ($x -and $all -notcontains $x) { $all += $x } } }
    }
    $note = "changes=" + ($all -join ',') + "`nxmx_before=" + $cur + "`nfile=" + $path + "`n"
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    [System.IO.File]::WriteAllText($jc, $note, $Utf8)
    return $changes
}

function Say-GameJson($info) {
    if ($info.Issues -contains 'broken') { Say 'ProjectZomboid64.json: BROKEN - Steam > Project Zomboid > Properties > Installed Files > Verify integrity' Yellow; return }
    if ($info.Issues -contains 'pzopt' -or $info.Issues -contains 'aot') { Say 'ProjectZomboid64.json: PZ Optimization left in it (press 1 to repair)' Yellow }
    else { Say ('ProjectZomboid64.json: ok, game RAM ' + [math]::Round($info.XmxMB / 1024, 1) + ' GB') Green }
    if ($info.Agents.Count -gt 0) { Say ('ProjectZomboid64.json: other start tools: ' + ($info.Agents -join ', ') + ' (left as they are)') Yellow }
}

try {
    Say ''
    Say '  Cookie Slicer Helper - Setup' Magenta
    Say '  (CPU / RAM in the Slicer window, game RAM set for your PC)' DarkGray
    Say ''
    Say '  [1] Install or update'
    Say '  [2] Uninstall'
    Say '  [3] Check'
    Say ''
    $choice = (Read-Host '  Type 1, 2 or 3 and press Enter').Trim()
    Say ("choice " + $choice) DarkGray
    if (@(Get-Process -Name 'ProjectZomboid64' -ErrorAction SilentlyContinue).Count -gt 0 -and $choice -ne '3') {
        Say 'Close Project Zomboid first, then run this again.' Yellow
        return
    }
    $steam = Get-SteamInfo
    $libs = @(Get-SteamLibraries $steam.Roots)
    $cfg = Get-LocalConfig $steam.Roots
    $now = Get-LaunchOptions $cfg
    Say ("steam: " + ($steam.Roots -join '; ') + " | config: " + $cfg + " | options now: " + $now) DarkGray
    $run = Join-Path $AppDir 'run.ps1'
    $ours = 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $run + '" %command%'
    $old = Strip-Ours $now

    if ($choice -eq '1') {
        $cacheDirs = @()
        if ($now) { foreach ($m in [regex]::Matches($now, '-cachedir=("([^"]+)"|(\S+))')) { $cacheDirs += ($m.Groups[2].Value + $m.Groups[3].Value) } }
        $src = Find-Jar $libs $cacheDirs
        if (-not $src) {
            Say 'The helper file was not found.' Yellow
            Say 'Join the Cookie Cheetah server once (Steam downloads the Cookie Slicer mod), close the game, then run this again.' Yellow
            return
        }
        Say ("helper from " + $src) DarkGray
        New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
        Copy-Item -LiteralPath $src -Destination (Join-Path $AppDir $JarName) -Force
        $runSrc = Join-Path (Split-Path -Parent $src) 'run.ps1'
        if (Test-Path -LiteralPath $runSrc) { Copy-Item -LiteralPath $runSrc -Destination $run -Force }
        if (-not (Test-Path -LiteralPath $run)) { throw 'run.ps1 is missing next to the helper file' }
        Say '[ok] Helper installed' Green

        $ram = Get-RecommendMB
        $cur = Get-CurrentHeapMB $libs
        if ($cur -gt $ram.Safe) {
            # more than this PC can spare: the PC runs out of RAM -> stalls, checksum kicks
            [System.IO.File]::WriteAllText((Join-Path $AppDir 'heap.txt'), "heap_mb=$($ram.Rec)`n", $Utf8)
            Say ("[ok] Game RAM: " + [math]::Round($cur / 1024, 1) + " GB is more than this PC can spare -> " + ($ram.Rec / 1024) + " GB (PC has " + [math]::Round($ram.Total / 1024) + " GB)") Green
        } elseif ($ram.Rec -gt $cur) {
            [System.IO.File]::WriteAllText((Join-Path $AppDir 'heap.txt'), "heap_mb=$($ram.Rec)`n", $Utf8)
            Say ("[ok] Game RAM: " + [math]::Round($cur / 1024, 1) + " GB -> " + ($ram.Rec / 1024) + " GB (PC has " + [math]::Round($ram.Total / 1024) + " GB)") Green
        } else {
            Say ("[ok] Game RAM kept: " + [math]::Round($cur / 1024, 1) + " GB (suggested " + ($ram.Rec / 1024) + " GB, change it in the Cookie Slicer window > Version Slicer)") Green
        }

        $gj = Find-GameJson $libs
        if ($gj) {
            $info = Read-GameJson $gj
            Say ("game json: " + $gj + " | issues: " + ($info.Issues -join ',') + " | Xmx " + $info.XmxMB + " | agents: " + ($info.Agents -join ',')) DarkGray
            if ($info.Issues -contains 'broken') {
                Say 'ProjectZomboid64.json is broken: Steam > Project Zomboid > Properties > Installed Files > Verify integrity, then press 1 again' Yellow
            } else {
                try {
                    $want = $ram.Rec; if ($cur -gt $want -and $cur -le ($ram.Total - 2048)) { $want = $cur }
                    $done = @(Repair-GameJson $gj $info $want $ram.Total)
                    if ($done -contains 'pzopt' -or $done -contains 'aot') { Say '[ok] ProjectZomboid64.json: PZ Optimization leftovers removed (backup kept)' Green }
                    if ($done -contains 'xmx') { Say ('[ok] ProjectZomboid64.json: game RAM ' + [math]::Round($info.XmxMB / 1024, 1) + ' GB -> ' + [math]::Round($want / 1024, 1) + ' GB') Green }
                    if ($done.Count -eq 0) { Say '[ok] ProjectZomboid64.json is fine' Green }
                } catch {
                    Say ('ProjectZomboid64.json not changed: ' + $_.Exception.Message) Yellow
                }
                if ($info.Agents.Count -gt 0) { Say ('Other start tools in ProjectZomboid64.json (left as they are): ' + ($info.Agents -join ', ')) Yellow }
            }
        } else {
            Say 'ProjectZomboid64.json not found (game folder unknown) - skipped' DarkGray
        }

        $menu = $false
        foreach ($z in @((Join-Path $env:USERPROFILE 'Zomboid')) + $cacheDirs) { if ($z -and (Set-MenuMod $z $true)) { $menu = $true } }
        if ($menu) { Say '[ok] Cookie Slicer button on the main menu' Green }

        if ($now -and $now -match 'CookieSlicer') {
            Say '[ok] Steam launch option already set' Green
        } elseif (-not $cfg) {
            Set-Clipboard -Value ($ours + ' ' + $old).Trim()
            Say 'Steam settings not found. Steam > Project Zomboid > Properties > Launch Options: Ctrl+A, Ctrl+V' Yellow
        } else {
            if ($now -and $now -match '%command%') {
                Say ("Your launch options already use another start tool; Cookie Slicer goes in front: " + $now) Yellow
                $old = ($now -replace '(?i)%command%', '').Trim()
            }
            $line = ($ours + ' ' + $old).Trim()
            $wasOpen = Close-Steam
            Set-LaunchOptions $cfg $line
            Say '[ok] Steam launch option set' Green
            if ($wasOpen -and $steam.Exe) { Start-Process $steam.Exe }
        }
        Say ''
        Say 'DONE. Start Project Zomboid as usual.' Green
        Say 'Update later: run this again and press 1.' DarkGray
    } elseif ($choice -eq '2') {
        if ($now -and $now -match 'CookieSlicer' -and $cfg) {
            $wasOpen = Close-Steam
            Set-LaunchOptions $cfg $old
            Say ('[ok] Steam launch option back to: "' + $old + '"') Green
            if ($wasOpen -and $steam.Exe) { Start-Process $steam.Exe }
        }
        $cacheDirs = @()
        if ($now) { foreach ($m in [regex]::Matches($now, '-cachedir=("([^"]+)"|(\S+))')) { $cacheDirs += ($m.Groups[2].Value + $m.Groups[3].Value) } }
        foreach ($z in @((Join-Path $env:USERPROFILE 'Zomboid')) + $cacheDirs) { if ($z) { $null = Set-MenuMod $z $false } }
        $jc = Join-Path $AppDir 'json-changes.txt'
        if (Test-Path -LiteralPath $jc) {
            $c = [System.IO.File]::ReadAllText($jc)
            $file = [regex]::Match($c, 'file=(.+)').Groups[1].Value.Trim()
            $bk = "$file.cookieslicer-backup"
            if ($c -match 'changes=xmx\s' -and (Test-Path -LiteralPath $bk) -and (Test-Path -LiteralPath $file)) {
                Copy-Item -LiteralPath $bk -Destination $file -Force
                Remove-Item -LiteralPath $bk -Force
                Say '[ok] ProjectZomboid64.json back as it was' Green
            } elseif (Test-Path -LiteralPath $bk) {
                Say ('ProjectZomboid64.json kept repaired (the old one had PZ Optimization in it): ' + $bk) DarkGray
            }
            Remove-Item -LiteralPath $jc -Force
        }
        foreach ($n in $JarName, 'heap.txt', 'ramsave.txt') {
            $f = Join-Path $AppDir $n
            if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
        }
        $pcFiles = @((Join-Path $env:USERPROFILE 'Zomboid\Lua\CookieSlicer_pc.txt'))
        $cd = Join-Path $AppDir 'cachedir.txt'
        if (Test-Path -LiteralPath $cd) { $pcFiles += (Join-Path ([System.IO.File]::ReadAllText($cd).Trim()) 'Lua\CookieSlicer_pc.txt') }
        foreach ($f in $pcFiles) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
        Say ''
        Say 'DONE. Helper removed; the game starts as before.' Green
    } else {
        $jar = Join-Path $AppDir $JarName
        if (Test-Path -LiteralPath $jar) { Say ("Helper: installed  (" + (Get-Item -LiteralPath $jar).LastWriteTime + ")") Green }
        else { Say 'Helper: not installed' Yellow }
        Say ("Game RAM from next start: " + [math]::Round((Get-CurrentHeapMB $libs) / 1024, 1) + " GB")
        if ($null -eq $now) { Say 'Steam launch option: could not read' Yellow }
        elseif ($now -match 'CookieSlicer') { Say 'Steam launch option: set' Green }
        else { Say 'Steam launch option: NOT set (press 1)' Yellow }
        $gj = Find-GameJson $libs
        if ($gj) { Say-GameJson (Read-GameJson $gj) } else { Say 'ProjectZomboid64.json: not found' Yellow }
    }
} catch {
    Say ''
    Say ("Error: " + $_.Exception.Message) Red
    Say ("at: " + $_.InvocationInfo.PositionMessage) DarkGray
    Say ("Send this file to an admin: " + $Log) Yellow
}
