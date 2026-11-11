<#
Builds tools\cookie-agent-test.jar (needed only by cookie-launch-test.ps1).
Needs a JDK 17+ (javac + jar). The game's jre64 has no javac.
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -Jdk "C:\Program Files\Java\jdk-21"
#>
param([string]$Jdk = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
if (-not $Jdk) { throw 'Pass -Jdk <JDK folder> or set JAVA_HOME.' }
$javac = Join-Path $Jdk 'bin\javac.exe'
$jarExe = Join-Path $Jdk 'bin\jar.exe'
$here = $PSScriptRoot
$out = Join-Path $here 'out'
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $out | Out-Null
& $javac --release 17 -d $out (Join-Path $here 'src\cookie\test\CookieAgentTest.java')
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
$dest = Join-Path (Split-Path $here -Parent) 'cookie-agent-test.jar'
& $jarExe --create --file $dest --manifest (Join-Path $here 'MANIFEST.MF') -C $out .
if ($LASTEXITCODE -ne 0) { throw 'jar failed' }
Remove-Item $out -Recurse -Force
Get-FileHash $dest -Algorithm SHA256 | Format-List
