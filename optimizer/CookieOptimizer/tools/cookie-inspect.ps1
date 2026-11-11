<#
cookie-inspect.ps1 - copy the Lua files of some Workshop mods into P:\Zomboid\Lua\_inspect
so Claude can read them (the Workshop folders are too deep for the desktop bridge).

It only copies files. It does not start or stop the game or the server.

Usage (PowerShell):
  powershell -ExecutionPolicy Bypass -File cookie-inspect.ps1                 # the default list below
  powershell -ExecutionPolicy Bypass -File cookie-inspect.ps1 3451167732,3790359901
  ... -Clean                                                                    # empty _inspect first
  ... -Grep LoadGridsquare                                                      # also list every line with this text
  ... -ScanAll -Grep collectgarbage                                             # search ALL Workshop mods, copy nothing

Output:
  _inspect\<id>_<ModFolder>\<version>__<side>__<path>.lua   (folders flattened with "__")
  _inspect\index.txt    one line per mod: id, mod folder, files, KB
  _inspect\events.txt   every "Events.<Name>.Add(" line: file:line: text
  _inspect\grep.txt     with -Grep: every line containing that text (plain text, not a regex)
  _inspect\grep-all.txt with -ScanAll -Grep: same, over every Workshop mod (nothing copied)
#>
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Ids,
    [string]$WorkshopDir = 'P:\cookiev1\steamapps\workshop\content\108600',
    [string]$OutDir = 'P:\Zomboid\Lua\_inspect',
    [string]$Grep = '',
    [switch]$ScanAll,
    [switch]$Clean
)
$ErrorActionPreference = 'Stop'

function Safe([string]$s) { return ($s -replace '[^A-Za-z0-9._-]', '') }

if ($ScanAll) {
    if (-not $Grep) { throw '-ScanAll needs -Grep <text>' }
    if (-not (Test-Path -LiteralPath $WorkshopDir)) { throw "Workshop folder not found: $WorkshopDir" }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $hitsAll = New-Object System.Collections.Generic.List[string]
    $mods = 0
    foreach ($item in Get-ChildItem -LiteralPath $WorkshopDir -Directory) {
        $modsDir = [IO.Path]::Combine($item.FullName, 'mods')
        if (-not (Test-Path -LiteralPath $modsDir)) { continue }
        foreach ($mod in Get-ChildItem -LiteralPath $modsDir -Directory) {
            $mods++
            $files = Get-ChildItem -LiteralPath $mod.FullName -Recurse -File -Filter '*.lua' -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $g = Select-String -LiteralPath $f.FullName -Pattern $Grep -SimpleMatch -ErrorAction SilentlyContinue
                foreach ($h in $g) {
                    $rel = $f.FullName.Substring($mod.FullName.Length).TrimStart('\', '/')
                    $rel = $rel -replace '[\\/]media[\\/]lua[\\/]', '\'
                    $flat = ($rel -split '[\\/]') -join '__'
                    $hitsAll.Add(('{0}_{1}/{2}:{3}: {4}' -f $item.Name, (Safe $mod.Name), $flat, $h.LineNumber, $h.Line.Trim()))
                }
            }
        }
    }
    [IO.File]::WriteAllLines([IO.Path]::Combine($OutDir, 'grep-all.txt'), $hitsAll)
    Write-Host ("searched {0} mods for '{1}': {2} lines -> {3}" -f $mods, $Grep, $hitsAll.Count, [IO.Path]::Combine($OutDir, 'grep-all.txt'))
    Write-Host 'Done. Tell Claude grep-all.txt is ready.'
    return
}

# Round 2 (10 Nov 2026 profiler): heaviest always-on client Lua + biggest spikes.
$Default = @(
    '3451167732',  # MS (ModernStatus)       render 3.1% core, max 16 ms
    '3790359901',  # LifestyleHobbies        OnTick 2.4%, EveryOneMinute max 34 ms
    '3803984183',  # ProjectALifeNPCs        client 7.5%, server 4.7%
    '3775673766',  # RarityThreads           OnTick 1.4%, max 27 ms
    '3290232938',  # SmarterStorage          prerender 1.2%, max 25 ms
    '3772269882',  # KnoxBuildworks          Loader max 76 ms
    '3821393562',  # AliveJeemDynamicWorld   server OnTick 3.7%
    '3461263912',  # CleanHotBar             render 1.1%
    '3821752171'   # SilentHillPyramidHead   OnZombieUpdate 1.2%
)

$list = @()
foreach ($a in @($Ids)) { if ($a) { $list += ($a -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' }) } }
if ($list.Count -eq 0) { $list = $Default }

if (-not (Test-Path -LiteralPath $WorkshopDir)) { throw "Workshop folder not found: $WorkshopDir" }
if ($Clean -and (Test-Path -LiteralPath $OutDir)) {
    Get-ChildItem -LiteralPath $OutDir -Force | Remove-Item -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$index =New-Object System.Collections.Generic.List[string]
$events = New-Object System.Collections.Generic.List[string]
$grepLines = New-Object System.Collections.Generic.List[string]
$index.Add(("{0,-12} {1,-36} {2,6} {3,8}" -f 'id', 'mod', 'files', 'KB'))

foreach ($id in $list) {
    $modsDir = [IO.Path]::Combine($WorkshopDir, $id, 'mods')
    if (-not (Test-Path -LiteralPath $modsDir)) {
        $index.Add(("{0,-12} {1}" -f $id, '(not downloaded on this PC)'))
        continue
    }
    foreach ($mod in Get-ChildItem -LiteralPath $modsDir -Directory) {
        $dest = [IO.Path]::Combine($OutDir, ($id + '_' + (Safe $mod.Name)))
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $count = 0; $bytes = 0
        $files = Get-ChildItem -LiteralPath $mod.FullName -Recurse -File |
            Where-Object { $_.Extension -eq '.lua' -or $_.Name -eq 'mod.info' }
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($mod.FullName.Length).TrimStart('\', '/')
            $rel = $rel -replace '[\\/]media[\\/]lua[\\/]', '\'
            $flat = ($rel -split '[\\/]') -join '__'
            Copy-Item -LiteralPath $f.FullName -Destination ([IO.Path]::Combine($dest, $flat)) -Force
            $count++; $bytes += $f.Length
            if ($f.Extension -eq '.lua') {
                $hits = Select-String -LiteralPath $f.FullName -Pattern 'Events\.\w+\.Add\s*\(' -ErrorAction SilentlyContinue
                foreach ($h in $hits) {
                    $events.Add(('{0}/{1}:{2}: {3}' -f (Split-Path $dest -Leaf), $flat, $h.LineNumber, $h.Line.Trim()))
                }
                if ($Grep) {
                    $g = Select-String -LiteralPath $f.FullName -Pattern $Grep -SimpleMatch -ErrorAction SilentlyContinue
                    foreach ($h in $g) {
                        $grepLines.Add(('{0}/{1}:{2}: {3}' -f (Split-Path $dest -Leaf), $flat, $h.LineNumber, $h.Line.Trim()))
                    }
                }
            }
        }
        $index.Add(("{0,-12} {1,-36} {2,6} {3,8}" -f $id, $mod.Name, $count, [math]::Round($bytes / 1KB)))
    }
}

[IO.File]::WriteAllLines([IO.Path]::Combine($OutDir, 'index.txt'), $index)
[IO.File]::WriteAllLines([IO.Path]::Combine($OutDir, 'events.txt'), $events)
$index | ForEach-Object { Write-Host $_ }
Write-Host ("events: {0} lines -> {1}" -f $events.Count, [IO.Path]::Combine($OutDir, 'events.txt'))
if ($Grep) {
    [IO.File]::WriteAllLines([IO.Path]::Combine($OutDir, 'grep.txt'), $grepLines)
    Write-Host ("grep '{0}': {1} lines -> {2}" -f $Grep, $grepLines.Count, [IO.Path]::Combine($OutDir, 'grep.txt'))
}
Write-Host 'Done. Tell Claude the files are in _inspect.'
