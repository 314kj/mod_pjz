# CookieCheetah mod scan. Read only: it only reads mod files and writes its
# report to P:\Zomboid\csp_scan (new folder). Nothing in the mods is changed.
param(
    [string]$Workshop = 'P:\cookiev1\steamapps\workshop\content\108600',
    [string]$LocalMods = 'P:\Zomboid\Workshop',
    [string]$Ini = 'P:\Zomboid\Server\cookiev1.ini',
    [string[]]$GameScripts = @('P:\cookiev1\media\scripts', 'P:\SteamLibrary\steamapps\common\ProjectZomboid\media\scripts'),
    [string]$Out = 'P:\Zomboid\csp_scan',
    [string]$GameVersion = '42.21',
    [string]$NeatBuildingId = '3536052310'
)
$ErrorActionPreference = 'SilentlyContinue'
$gameVer = [version]$GameVersion
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$sep = [IO.Path]::DirectorySeparatorChar

# mods switched on in the server ini
$enabled = @{}
$modsLine = Get-Content $Ini | Where-Object { $_ -like 'Mods=*' } | Select-Object -First 1
foreach ($m in ($modsLine -replace '^Mods=', '').Split(';')) {
    $id = $m.Trim().TrimStart('\')
    if ($id) { $enabled[$id] = $true }
}

# every mod folder: workshop items + the host's own Workshop folder
$modDirs = New-Object System.Collections.Generic.List[object]
Get-ChildItem $Workshop -Directory | ForEach-Object {
    $wid = $_.Name
    Get-ChildItem (Join-Path $_.FullName 'mods') -Directory | ForEach-Object { $modDirs.Add(@($wid, $_.FullName)) }
}
Get-ChildItem $LocalMods -Directory | ForEach-Object {
    $wid = 'local:' + $_.Name
    Get-ChildItem (Join-Path (Join-Path $_.FullName 'Contents') 'mods') -Directory | ForEach-Object { $modDirs.Add(@($wid, $_.FullName)) }
}

function Get-ActiveFolders($modDir) {
    $best = $null; $bestV = $null
    foreach ($d in (Get-ChildItem $modDir -Directory)) {
        if ($d.Name -notmatch '^\d+(\.\d+)?$') { continue }
        $n = $d.Name; if ($n -notmatch '\.') { $n = $n + '.0' }
        $v = [version]$n
        if ($v -le $gameVer -and ($bestV -eq $null -or $v -gt $bestV)) { $best = $d.FullName; $bestV = $v }
    }
    $list = @()
    if ($best) { $list += $best }
    $common = Join-Path $modDir 'common'
    if (Test-Path $common) { $list += $common }
    return , $list
}

function Get-ModId($folders, $modDir) {
    foreach ($f in @($folders + $modDir)) {
        $info = Join-Path $f 'mod.info'
        if (Test-Path $info) {
            $line = Get-Content $info | Where-Object { $_ -match '^\s*id\s*=' } | Select-Object -First 1
            if ($line) { return (($line -replace '^\s*id\s*=\s*', '').Trim().TrimStart('\')) }
        }
    }
    return $null
}

$events = @('LoadGridsquare', 'ReuseGridsquare', 'LoadChunk', 'OnZombieUpdate', 'OnPlayerUpdate', 'OnTick', 'OnTickEvenPaused', 'OnRenderTick', 'OnObjectAdded')
$bundleEvents = @('LoadGridsquare', 'ReuseGridsquare', 'LoadChunk', 'OnZombieUpdate')
$rx = 'Events\s*(?:\.\s*|\[\s*["''])(\w+)["'']?\s*\]?\s*\.\s*Add\s*\('

$rows = New-Object System.Collections.Generic.List[string]
$java = New-Object System.Collections.Generic.List[string]
$bundle = New-Object System.Text.StringBuilder
$found = @{}

foreach ($md in $modDirs) {
    $wid = $md[0]; $modDir = $md[1]
    $folders = Get-ActiveFolders $modDir
    $id = Get-ModId $folders $modDir
    if (-not $id -or -not $enabled.ContainsKey($id)) { continue }
    $found[$id] = $true
    foreach ($a in $folders) {
        $jar = Get-ChildItem $a -Recurse -File | Where-Object { $_.Extension -eq '.jar' -or $_.Extension -eq '.class' } | Select-Object -First 1
        if ($jar) { $java.Add("$wid`t$id`t" + $jar.FullName.Substring($a.Length)) }
        $luaDir = Join-Path (Join-Path $a 'media') 'lua'
        foreach ($f in (Get-ChildItem $luaDir -Recurse -File -Filter *.lua)) {
            $rel = (Split-Path $a -Leaf) + $f.FullName.Substring($a.Length)
            $text = [IO.File]::ReadAllText($f.FullName)
            $toBundle = $false
            foreach ($h in [regex]::Matches($text, $rx)) {
                $ev = $h.Groups[1].Value
                if ($events -notcontains $ev) { continue }
                $line = ($text.Substring(0, $h.Index) -split "`n").Count
                $rows.Add("$ev`t$id`t$wid`t$rel`:$line")
                if ($bundleEvents -contains $ev) { $toBundle = $true }
            }
            if ($toBundle) {
                [void]$bundle.AppendLine("===== $id | $wid | $rel")
                [void]$bundle.AppendLine($text)
            }
        }
    }
}

$r = New-Object System.Text.StringBuilder
[void]$r.AppendLine("CSP mod scan " + (Get-Date -Format 'yyyy-MM-dd HH:mm') + " game $GameVersion")
[void]$r.AppendLine("mods on in ini: " + $enabled.Count + " | found on disk: " + $found.Count)
[void]$r.AppendLine("")
[void]$r.AppendLine("== per-event counts (event / mods)")
foreach ($ev in $events) {
    $mods = $rows | Where-Object { $_.Split("`t")[0] -eq $ev } | ForEach-Object { $_.Split("`t")[1] } | Sort-Object -Unique
    [void]$r.AppendLine("$ev`t" + @($mods).Count + "`t" + (@($mods) -join ', '))
}
[void]$r.AppendLine("")
[void]$r.AppendLine("== handlers (event, mod id, workshop id, file:line)")
foreach ($x in ($rows | Sort-Object)) { [void]$r.AppendLine($x) }
[void]$r.AppendLine("")
[void]$r.AppendLine("== mods with Java files (.jar/.class)")
foreach ($x in $java) { [void]$r.AppendLine($x) }
[void]$r.AppendLine("")
[void]$r.AppendLine("== mods on in ini but not found on disk")
foreach ($k in ($enabled.Keys | Sort-Object)) { if (-not $found.ContainsKey($k)) { [void]$r.AppendLine($k) } }

# who defines the grass floor entities (Neat Building and the game itself)
$nb = New-Object System.Text.StringBuilder
$pat = 'blends_natural|blends_street|Floor_SpringGrass|Floor_SummerGrass|Floor_FallGrass'
$nbRoot = Join-Path (Join-Path $Workshop $NeatBuildingId) 'mods'
foreach ($m in (Get-ChildItem $nbRoot -Directory)) {
    foreach ($a in (Get-ActiveFolders $m.FullName)) {
        foreach ($f in (Get-ChildItem $a -Recurse -File | Where-Object { $_.Extension -eq '.txt' -or $_.Extension -eq '.lua' })) {
            $t = [IO.File]::ReadAllText($f.FullName)
            if ($t -match $pat) {
                [void]$nb.AppendLine("===== NB " + $m.Name + " | " + (Split-Path $a -Leaf) + $f.FullName.Substring($a.Length))
                [void]$nb.AppendLine($t)
            }
        }
    }
}
foreach ($g in $GameScripts) {
    if (-not (Test-Path $g)) { [void]$nb.AppendLine("===== GAME $g (not found)"); continue }
    $hits = Get-ChildItem $g -Recurse -File -Filter *.txt | Select-String -Pattern 'Floor_SpringGrass|blends_natural_01_16\b' -Context 4, 12 | Select-Object -First 30
    [void]$nb.AppendLine("===== GAME $g : " + @($hits).Count + " hit(s)")
    foreach ($h in $hits) {
        [void]$nb.AppendLine("--- " + $h.Path.Substring($g.Length) + ":" + $h.LineNumber)
        foreach ($c in $h.Context.PreContext) { [void]$nb.AppendLine("  " + $c) }
        [void]$nb.AppendLine("> " + $h.Line)
        foreach ($c in $h.Context.PostContext) { [void]$nb.AppendLine("  " + $c) }
    }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Out 'report.txt'), $r.ToString(), $utf8)
[IO.File]::WriteAllText((Join-Path $Out 'handlers_bundle.txt'), $bundle.ToString(), $utf8)
[IO.File]::WriteAllText((Join-Path $Out 'grass_bundle.txt'), $nb.ToString(), $utf8)
"done: " + $found.Count + " mods scanned, " + $rows.Count + " handlers -> $Out"
