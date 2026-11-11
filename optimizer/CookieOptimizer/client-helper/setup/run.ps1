# Cookie Slicer - game start script, used as the game's Steam launch option:
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<this file>" %command%
# Steam passes the game's exe and its options. This adds the Cookie Slicer Helper (when
# its jar is next to this file) and the game RAM chosen in the Slicer window (heap.txt),
# then starts the game and waits for it. Any missing piece: the game starts as usual.
# No game file is changed. Copyright (c) AKA / Cookie Cheetah.
$exe = $args[0]
$rest = @()
if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)]) }
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Java refuses to start at all when an agent jar is broken, so only a jar that
# really is the helper is used (otherwise the game starts without it)
function Test-Agent([string]$jar) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [System.IO.Compression.ZipFile]::OpenRead($jar)
        try {
            $e = $z.GetEntry('META-INF/MANIFEST.MF')
            if (-not $e) { return $false }
            $r = New-Object System.IO.StreamReader($e.Open())
            $t = $r.ReadToEnd()
            $r.Close()
            return $t -match 'Premain-Class:\s*cookie\.slicer\.helper\.Helper'
        } finally { $z.Dispose() }
    } catch { return $false }
}

try {
    # the game starts Java itself; Java's agent library needs the game's own Java folder on PATH
    $jre = Join-Path (Split-Path -Parent $exe) 'jre64\bin'
    if (Test-Path -LiteralPath $jre) { $env:PATH = $jre + ';' + $env:PATH }
    $jar = Join-Path $here 'CookieSlicerHelper.jar'
    if ((Test-Path -LiteralPath $jar) -and (Test-Agent $jar)) {
        # the game's exe gives Java no command line to read, so tell the helper it runs
        # in the game client and where the game keeps its files (-cachedir)
        $opt = 'client'
        foreach ($a in $rest) { if ("$a" -like '-cachedir=*') { $opt += ';cachedir=' + ("$a".Substring(10).Trim('"')) } }
        $env:JAVA_TOOL_OPTIONS = '"-javaagent:' + $jar + '=' + $opt + '"'
    }
    $hf = Join-Path $here 'heap.txt'
    if (Test-Path -LiteralPath $hf) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($hf), 'heap_mb=(\d+)')
        if ($m.Success) {
            $mb = [int]$m.Groups[1].Value
            if ($mb -ge 2048 -and $mb -le 32768) { $env:_JAVA_OPTIONS = "-Xmx$($mb)m" }
        }
    }
} catch { }
& $exe @rest
exit $LASTEXITCODE
