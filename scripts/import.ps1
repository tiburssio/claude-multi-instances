# Importa o perfil padrão do Claude/Cursor/Codex para instâncias isoladas.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/import.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/import.ps1 -Service claude

param(
    [ValidateSet("claude", "cursor", "codex")]
    [string]$Service
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\common.ps1")

$instances = @(Get-Instances -Filter $Service)
$services = @($instances.Service | Select-Object -Unique)
foreach ($svc in $services) {
    $names = @($instances | Where-Object { $_.Service -eq $svc } | ForEach-Object { $_.Name })
    Prompt-AndImportDefaultData -Service $svc -Names $names
}
