# Cookie Slicer - game start script, used as the game's Steam launch option:
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<this file>" %command%
# Steam passes the game's exe and its options. This adds the Cookie Slicer Helper (when
# its jar is next to this file), the game RAM chosen in the Slicer window (heap.txt) and
# Java's own RAM savers (unless turned off in the window: ramsave.txt says ramsave=0),
# then starts the game and waits for it. Any missing piece: the game starts as usual.
# No game file is changed. Copyright (c) AKA / Cookie Cheetah.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$self = $MyInvocation.MyCommand.Path

# The options exactly as Steam gave them. PowerShell's -File splits "-name:value" into
# "-name" "value" ($args), so "-agentlib:zbNative" (ZombieBuddy) reached Java as a bare
# "-agentlib" and the game closed at once. Windows' own splitter on the raw command line
# keeps them whole; $args only when that fails.
function Get-RawArgs {
    try {
        Add-Type -Namespace CookieSlicer -Name Argv -MemberDefinition @'
[DllImport("shell32.dll")] public static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string cmd, out int n);
[DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
'@
        $n = 0
        $p = [CookieSlicer.Argv]::CommandLineToArgvW([Environment]::CommandLine, [ref]$n)
        if ($p -eq [IntPtr]::Zero) { return $null }
        $all = @()
        for ($i = 0; $i -lt $n; $i++) {
            $all += [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::ReadIntPtr($p, $i * [IntPtr]::Size))
        }
        $null = [CookieSlicer.Argv]::LocalFree($p)
        for ($i = 0; $i -lt $all.Count - 1; $i++) {
            # the comma keeps a list of one (only the game's exe: no launch options of the
            # player's own) a list; PowerShell would hand back the bare text and $cmd[0]
            # below would be its first letter ("C"), so the game never started
            if ($all[$i] -eq $self) { return ,@($all[($i + 1)..($all.Count - 1)]) }
        }
    } catch { }
    return $null
}

$cmd = Get-RawArgs
if (-not $cmd) { $cmd = @($args) }
$exe = $cmd[0]
$rest = @()
if ($cmd.Count -gt 1) { $rest = @($cmd[1..($cmd.Count - 1)]) }

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
    # mode.txt "mode=compat" (chosen in the setup): for other Java mods (ZombieBuddy /
    # Viewpoint) - no helper and no RAM savers, only the game RAM
    $compat = $false
    $mf = Join-Path $here 'mode.txt'
    if ((Test-Path -LiteralPath $mf) -and ([System.IO.File]::ReadAllText($mf) -match 'mode=compat')) { $compat = $true }
    $jar = Join-Path $here 'CookieSlicerHelper.jar'
    if (-not $compat -and (Test-Path -LiteralPath $jar) -and (Test-Agent $jar)) {
        # the game's exe gives Java no command line to read, so tell the helper it runs
        # in the game client and where the game keeps its files (-cachedir)
        $opt = 'client'
        foreach ($a in $rest) { if ("$a" -like '-cachedir=*') { $opt += ';cachedir=' + ("$a".Substring(10).Trim('"')) } }
        # added to what another tool may have put there, not in its place
        $env:JAVA_TOOL_OPTIONS = ('"-javaagent:' + $jar + '=' + $opt + '" ' + $env:JAVA_TOOL_OPTIONS).Trim()
    }
    $jo = @()
    $mb = 0
    $hf = Join-Path $here 'heap.txt'
    if (Test-Path -LiteralPath $hf) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($hf), 'heap_mb=(\d+)')
        if ($m.Success) {
            $v = [int]$m.Groups[1].Value
            if ($v -ge 2048 -and $v -le 32768) { $mb = $v; $jo += "-Xmx$($mb)m" }
        }
    }
    # RAM savers (Java 25, the game's own Java): smaller object headers, one copy of
    # repeated text, keep the memory under 4/5 of the RAM above when it can and give
    # what is not used back to Windows after a minute. A flag this Java does not know is skipped.
    $save = $true
    $sf = Join-Path $here 'ramsave.txt'
    if ($compat -or ((Test-Path -LiteralPath $sf) -and ([System.IO.File]::ReadAllText($sf) -match 'ramsave=0'))) { $save = $false }
    if ($save) {
        $jo += '-XX:+IgnoreUnrecognizedVMOptions', '-XX:+UseCompactObjectHeaders', '-XX:+UseStringDeduplication', '-XX:ZUncommitDelay=60'
        if ($mb -gt 0) { $jo += "-XX:SoftMaxHeapSize=$([math]::Floor($mb * 4 / 5))m" }
    }
    if ($jo.Count -gt 0) { $env:_JAVA_OPTIONS = (($env:_JAVA_OPTIONS + ' ' + ($jo -join ' ')).Trim()) }
} catch { }
& $exe @rest
exit $LASTEXITCODE
