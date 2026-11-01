# CookieCheetah: what each mod to be removed leaves in the world. Read only:
# it only reads mod files and writes P:\Zomboid\csp_scan\removecheck.txt and
# P:\Zomboid\csp_scan\entities_bundle.txt. Nothing in the mods or the save is changed.
param(
    [string[]]$Libraries = @('P:\cookiev1\steamapps\workshop\content\108600',
                             'P:\SteamLibrary\steamapps\workshop\content\108600',
                             'C:\Program Files (x86)\Steam\steamapps\workshop\content\108600'),
    [string]$Ini = 'P:\Zomboid\Server\cookiev1.ini',
    [string]$Out = 'P:\Zomboid\csp_scan',
    [string]$GameVersion = '42.21',
    [string[]]$Targets = @('3791152383', '3812370808', '3766513120', '3807510799', '3806443105', '3787526143'),
    [string[]]$Extra = @('3743063232')
)
$ErrorActionPreference = 'SilentlyContinue'
$gameVer = [version]$GameVersion
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$enabled = @{}
$modsLine = Get-Content $Ini | Where-Object { $_ -like 'Mods=*' } | Select-Object -First 1
foreach ($m in ($modsLine -replace '^Mods=', '').Split(';')) { $id = $m.Trim().TrimStart('\'); if ($id) { $enabled[$id] = $true } }

function Find-Item($wid) {
    foreach ($lib in $Libraries) { $p = Join-Path $lib $wid; if (Test-Path $p) { return $p } }
    return $null
}
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
function Get-InfoValue($folders, $modDir, $key) {
    foreach ($f in @($folders + $modDir)) {
        $info = Join-Path $f 'mod.info'
        if (Test-Path $info) {
            $line = Get-Content $info | Where-Object { $_ -match ('^\s*' + $key + '\s*=') } | Select-Object -First 1
            if ($line) { return (($line -replace ('^\s*' + $key + '\s*=\s*'), '').Trim()) }
        }
    }
    return ''
}
# find the block that starts at the "{" at or after $start; returns end index
function Get-BlockEnd([string]$t, [int]$start) {
    $i = $t.IndexOf('{', $start); if ($i -lt 0) { return -1 }
    $depth = 0
    for ($j = $i; $j -lt $t.Length; $j++) {
        $c = $t[$j]
        if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $j } }
    }
    return $t.Length - 1
}

$r = New-Object System.Text.StringBuilder
$ents = New-Object System.Text.StringBuilder
[void]$r.AppendLine("CSP remove check " + (Get-Date -Format 'yyyy-MM-dd HH:mm') + " game $GameVersion")

# which enabled mods require what (to find mods that depend on the ones being removed)
$requires = @{}
foreach ($lib in $Libraries) {
    foreach ($item in (Get-ChildItem $lib -Directory)) {
        foreach ($md in (Get-ChildItem (Join-Path $item.FullName 'mods') -Directory)) {
            $f = Get-ActiveFolders $md.FullName
            $id = (Get-InfoValue $f $md.FullName 'id').TrimStart('\')
            if (-not $id -or -not $enabled.ContainsKey($id) -or $requires.ContainsKey($id)) { continue }
            $requires[$id] = (Get-InfoValue $f $md.FullName 'require')
        }
    }
}

foreach ($wid in @($Targets + $Extra)) {
    $path = Find-Item $wid
    [void]$r.AppendLine("")
    [void]$r.AppendLine("################ workshop $wid " + $(if ($path) { $path } else { '(not on disk)' }))
    if (-not $path) { continue }
    foreach ($md in (Get-ChildItem (Join-Path $path 'mods') -Directory)) {
        $folders = Get-ActiveFolders $md.FullName
        $id = (Get-InfoValue $folders $md.FullName 'id').TrimStart('\')
        $on = $enabled.ContainsKey($id)
        [void]$r.AppendLine("=== mod " + $md.Name + " | id=" + $id + " | on in ini: " + $on + " | active: " + (($folders | ForEach-Object { Split-Path $_ -Leaf }) -join ', '))
        [void]$r.AppendLine("name: " + (Get-InfoValue $folders $md.FullName 'name'))
        [void]$r.AppendLine("require: " + (Get-InfoValue $folders $md.FullName 'require'))
        $needers = @(); foreach ($k in $requires.Keys) { if ($requires[$k] -match ('(^|[,;\s\\])' + [regex]::Escape($id) + '($|[,;\s])')) { $needers += $k } }
        [void]$r.AppendLine("required by (on in ini): " + ($needers -join ', '))
        $files = @(); foreach ($a in $folders) { $files += Get-ChildItem $a -Recurse -File }
        $byExt = $files | Group-Object { $_.Extension.ToLower() } | Sort-Object Count -Descending | ForEach-Object { $_.Name + '=' + $_.Count }
        [void]$r.AppendLine("files: " + ($byExt -join ' '))
        $tiles = $files | Where-Object { $_.Extension -eq '.tiles' -or $_.Extension -eq '.pack' } | ForEach-Object { $_.Name }
        [void]$r.AppendLine("tiles/packs: " + ($tiles -join ', '))
        $spriteEnts = @(); $tilesets = @{}; $items = 0; $itemNames = @(); $recipes = 0; $vehicles = 0; $sandbox = @(); $hints = @()
        foreach ($f in ($files | Where-Object { $_.Extension -eq '.txt' })) {
            $t = [IO.File]::ReadAllText($f.FullName)
            if ($f.Name -eq 'sandbox-options.txt') {
                foreach ($m in [regex]::Matches($t, '(?m)^\s*option\s+([\w\.]+)')) { $sandbox += $m.Groups[1].Value }
                continue
            }
            foreach ($m in [regex]::Matches($t, '(?m)^\s*item\s+(\w+)\s*\r?\n?\s*\{')) { $items++; if ($itemNames.Count -lt 400) { $itemNames += $m.Groups[1].Value } }
            $recipes += [regex]::Matches($t, '(?m)^\s*craftRecipe\s+\w+').Count
            $vehicles += [regex]::Matches($t, '(?m)^\s*vehicle\s+\w+').Count
            if ($t -match 'component\s+SpriteConfig') {
                $mod = 'Base'; $mm = [regex]::Match($t, '(?m)^\s*module\s+(\w+)'); if ($mm.Success) { $mod = $mm.Groups[1].Value }
                foreach ($m in [regex]::Matches($t, '\bentity\s+([\w\.]+)\s*\{')) {
                    $end = Get-BlockEnd $t $m.Index
                    $block = $t.Substring($m.Index, [Math]::Max(0, $end - $m.Index + 1))
                    if ($block -notmatch 'component\s+SpriteConfig') { continue }
                    $spriteEnts += ($mod + '.' + $m.Groups[1].Value)
                    foreach ($row in [regex]::Matches($block, 'row\s*=\s*([^,\r\n]+)')) {
                        foreach ($s in ($row.Groups[1].Value -split '\s+')) { if ($s) { $ts = ($s -replace '_\d+$', ''); $tilesets[$ts] = $true } }
                    }
                }
                [void]$ents.AppendLine("===== $wid | $id | " + $f.FullName.Substring($path.Length))
                [void]$ents.AppendLine($t)
            }
        }
        foreach ($f in ($files | Where-Object { $_.Extension -eq '.lua' })) {
            $t = [IO.File]::ReadAllText($f.FullName)
            foreach ($m in [regex]::Matches($t, '(?i)[^\r\n]{0,60}(uninstall|prepare\s*to\s*remove|before\s+remov|safe\s*remov)[^\r\n]{0,60}')) {
                if ($hints.Count -lt 15) { $hints += ($f.Name + ': ' + $m.Value.Trim()) }
            }
        }
        [void]$r.AppendLine("SpriteConfig entities (WorldDictionary risk): " + $spriteEnts.Count + " " + (($spriteEnts | Select-Object -First 80) -join ', '))
        [void]$r.AppendLine("tilesets used by those entities: " + (($tilesets.Keys | Sort-Object) -join ', '))
        [void]$r.AppendLine("items: $items | craftRecipes: $recipes | vehicles: $vehicles")
        [void]$r.AppendLine("item names: " + ($itemNames -join ', '))
        [void]$r.AppendLine("sandbox options: " + ($sandbox -join ', '))
        [void]$r.AppendLine("uninstall hints in lua: ")
        foreach ($h in $hints) { [void]$r.AppendLine("  " + $h) }
    }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Out 'removecheck.txt'), $r.ToString(), $utf8)
[IO.File]::WriteAllText((Join-Path $Out 'entities_bundle.txt'), $ents.ToString(), $utf8)
"done -> " + (Join-Path $Out 'removecheck.txt')
