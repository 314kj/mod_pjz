# CookieCheetah: build the tiles-only mod "CookieRemovedTiles" from mods that are
# being removed (Building Clipboard stairs/roofs, Blackout Predators Extended nests),
# so objects already in the world keep their picture and (for stairs) still work.
# Read only on the source mods: it copies their .tiles/.pack files and writes a new
# folder P:\Zomboid\Workshop\CookieServerPatch\Contents\mods\CookieRemovedTiles.
# It does not start/stop the server and does not touch the save.
param(
    [string]$Workshop = 'P:\cookiev1\steamapps\workshop\content\108600',
    [string[]]$Sources = @('3812370808', '3807510799'),
    [string]$Dest = 'P:\Zomboid\Workshop\CookieServerPatch\Contents\mods\CookieRemovedTiles',
    [string]$GameVersion = '42.21'
)
$ErrorActionPreference = 'Stop'
$gameVer = [version]$GameVersion

function Get-ActiveFolders($modDir) {
    $best = $null; $bestV = $null
    foreach ($d in (Get-ChildItem $modDir -Directory)) {
        if ($d.Name -notmatch '^\d+(\.\d+)?$') { continue }
        $n = $d.Name; if ($n -notmatch '\.') { $n = $n + '.0' }
        $v = [version]$n
        if ($v -le $gameVer -and ($bestV -eq $null -or $v -gt $bestV)) { $best = $d.FullName; $bestV = $v }
    }
    $list = @(); if ($best) { $list += $best }
    $common = Join-Path $modDir 'common'; if (Test-Path $common) { $list += $common }
    return , $list
}
# value of "key=..." in mod.info lines, '' when the key is missing
function Get-Val($lines, [string]$key) {
    $l = $lines | Where-Object { $_ -match ('^\s*' + $key + '\s*=') } | Select-Object -First 1
    if ($null -eq $l) { return '' }
    return (([string]$l) -replace ('^\s*' + $key + '\s*=\s*'), '').Trim()
}
function Find-File($folders, $name) {
    foreach ($f in $folders) {
        $hit = Get-ChildItem $f -Recurse -File -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$media = Join-Path (Join-Path $Dest '42') 'media'
$tp = Join-Path $media 'texturepacks'
New-Item -ItemType Directory -Force -Path $tp | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'common') | Out-Null

$lines = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]
$seen = @{}
foreach ($wid in $Sources) {
    $item = Join-Path $Workshop $wid
    if (-not (Test-Path $item)) { $notes.Add("MISSING workshop item $wid"); continue }
    foreach ($md in (Get-ChildItem (Join-Path $item 'mods') -Directory)) {
        $folders = Get-ActiveFolders $md.FullName
        $info = $null
        foreach ($f in @($folders + $md.FullName)) { $p = Join-Path $f 'mod.info'; if (Test-Path $p) { $info = $p; break } }
        if (-not $info) { continue }
        $text = Get-Content $info
        $id = Get-Val $text 'id'
        $ver = Get-Val $text 'modversion'
        $notes.Add("source $wid $id version=$ver mod.info=$info")
        foreach ($l in $text) {
            if ($l -match '^\s*tiledef\s*=\s*(\S+)\s+(\d+)') {
                $name = $Matches[1]; $num = $Matches[2]
                if ($seen.ContainsKey("t:$name")) { continue }
                $src = Find-File $folders ($name + '.tiles')
                if (-not $src) { $notes.Add("  NOT FOUND $name.tiles"); continue }
                Copy-Item $src (Join-Path $media ($name + '.tiles')) -Force
                $lines.Add("tiledef=$name $num"); $seen["t:$name"] = $true
                $notes.Add("  tiledef $name $num <- $src  md5=" + (Get-FileHash $src -Algorithm MD5).Hash)
            } elseif ($l -match '^\s*pack\s*=\s*(\S+)') {
                $name = $Matches[1]
                if ($seen.ContainsKey("p:$name")) { continue }
                $src = Find-File $folders ($name + '.pack')
                if (-not $src) { $notes.Add("  NOT FOUND $name.pack"); continue }
                Copy-Item $src (Join-Path $tp ($name + '.pack')) -Force
                $lines.Add("pack=$name"); $seen["p:$name"] = $true
                $notes.Add("  pack $name <- $src  md5=" + (Get-FileHash $src -Algorithm MD5).Hash)
            }
        }
    }
}

$info = @(
    'name=Cookie - Removed Mod Tiles',
    'id=CookieRemovedTiles',
    'description=Tiles only, no code. Keeps the tiles of mods removed from CookieCheetah (Building Clipboard stairs and roof pieces, Blackout Predators Extended nest props) so objects already in the world keep their picture and stairs still work. Never turn it on together with the mods it replaces (same tile numbers).',
    'versionMin=42.0.0'
) + $lines
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines((Join-Path (Join-Path $Dest '42') 'mod.info'), [string[]]$info, $utf8)
[IO.File]::WriteAllLines((Join-Path $Dest 'common\readme.txt'), [string[]]@('Tiles-only mod. See 42/mod.info.'), $utf8)
[IO.File]::WriteAllLines((Join-Path $Dest 'SOURCES.txt'), [string[]]$notes, $utf8)
$notes
"mod.info:"
$info
"done -> $Dest"
