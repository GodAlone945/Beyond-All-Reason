[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "C# compiler missing: $compiler" }
$output = [IO.Path]::GetFullPath($OutputDirectory)
$scripts = Join-Path $output 'scripts'
$distribution = Join-Path $scripts 'pve-distribution'
New-Item -ItemType Directory -Path $distribution -Force | Out-Null
& $compiler /nologo /target:winexe ("/out:" + (Join-Path $output 'BAR-Custom-Test-Launcher.exe')) /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll (Join-Path $root 'Program.cs')
if ($LASTEXITCODE -ne 0) { throw "C# compilation failed: $LASTEXITCODE" }
foreach ($name in @('BarClientConfig.ps1', 'Invoke-BarClientLauncher.ps1', 'Invoke-BarPveMode.ps1')) {
    Copy-Item -LiteralPath (Join-Path (Join-Path $root 'scripts') $name) -Destination (Join-Path $scripts $name) -Force
}
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $root) 'pve-distribution\Update-BarPve.ps1') -Destination (Join-Path $distribution 'Update-BarPve.ps1') -Force
Write-Output "Launcher built: $output"
