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
# [2] Uninstall - removes the helper, our part of the launch option and the main-menu line.
# [3] Check.
# No game file is changed. It never starts or closes the game.
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

# RAM that fits this PC: half of it, 4-16 GB, at least 4 GB left (never under 3 GB)
function Get-RecommendMB {
    $total = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
    $rec = [math]::Round($total * 0.5 / 1024) * 1024
    $rec = [math]::Max(4096, [math]::Min(16384, $rec))
    if ($total - $rec -lt 4096) { $rec = [math]::Max(3072, [math]::Floor(($total - 4096) / 1024) * 1024) }
    return @{ Total = $total; Rec = [int]$rec }
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
        if ($ram.Rec -gt $cur) {
            [System.IO.File]::WriteAllText((Join-Path $AppDir 'heap.txt'), "heap_mb=$($ram.Rec)`n", $Utf8)
            Say ("[ok] Game RAM: " + [math]::Round($cur / 1024, 1) + " GB -> " + ($ram.Rec / 1024) + " GB (PC has " + [math]::Round($ram.Total / 1024) + " GB)") Green
        } else {
            Say ("[ok] Game RAM already fine: " + [math]::Round($cur / 1024, 1) + " GB (PC has " + [math]::Round($ram.Total / 1024) + " GB)") Green
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
        foreach ($n in $JarName, 'heap.txt') {
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
    }
} catch {
    Say ''
    Say ("Error: " + $_.Exception.Message) Red
    Say ("at: " + $_.InvocationInfo.PositionMessage) DarkGray
    Say ("Send this file to an admin: " + $Log) Yellow
}
