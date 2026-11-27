[CmdletBinding()]
param(
    [string]$PluginPath = 'C:\ProgramData\aviutl2\Plugin\SYNC_SignalLight\SYNC_SignalLight.auf2',
    [string]$ImageDirectory
)

$ErrorActionPreference = 'Stop'
$resolvedPlugin = (Resolve-Path -LiteralPath $PluginPath).Path
$out = Join-Path (Split-Path -Parent $PSScriptRoot) 'Win64\Verification'
$dcu = Join-Path $out 'DCU'
if (-not $ImageDirectory) {
    $ImageDirectory = Join-Path $out 'Images'
}
$ImageDirectory = [IO.Path]::GetFullPath($ImageDirectory)
$studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$lib = Join-Path $studio 'lib\Win64\release'
$null = New-Item -ItemType Directory -Path $dcu -Force

Push-Location $PSScriptRoot
try {
    & "$studio\bin\dcc64.exe" '--no-config' '-B' '-Q' '-TX.exe' '-$R+' '-$Q+' '-NSSystem;Winapi;Vcl' `
        "-U$lib;$lib\JA" "-E$out" "-NU$dcu" 'SignalLight_Auf2Tests.dpr'
    if ($LASTEXITCODE -ne 0) {
        throw "Test compilation failed (exit $LASTEXITCODE)."
    }
} finally {
    Pop-Location
}

& (Join-Path $out 'SignalLight_Auf2Tests.exe') $resolvedPlugin $ImageDirectory
if ($LASTEXITCODE -ne 0) {
    throw "AUF2 checks failed (exit $LASTEXITCODE)."
}
