# Remove atalhos e dados isolados. Não mexe no app nem no perfil original.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/remove.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/remove.ps1 -Instance claude:personal,cursor:work
#   powershell -ExecutionPolicy Bypass -File scripts/remove.ps1 -Service claude
#   powershell -ExecutionPolicy Bypass -File scripts/remove.ps1 -Service all -Yes

param(
    [ValidateSet("claude", "cursor", "all")]
    [string]$Service,

    [string[]]$Instance,

    [switch]$Yes
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\common.ps1")

if (-not $Service -and -not $Instance) {
    Prompt-AndRemoveInstances -Yes:$Yes
    return
}

$items = @(Get-Instances)
$selected = @()

if ($Instance) {
    foreach ($key in $Instance) {
        $parts = $key.Split(":", 2)
        if ($parts.Count -ne 2) {
            throw "Instância inválida: $key (use serviço:nome)"
        }
        $match = @($items | Where-Object { $_.Service -eq $parts[0] -and $_.Name -eq $parts[1] })
        if ($match.Count -eq 0) {
            throw "Não achei $key em $InstancesConf"
        }
        $selected += $match[0]
    }
}

if ($Service) {
    $services = if ($Service -eq "all") { @("claude", "cursor") } else { @($Service) }
    foreach ($svc in $services) {
        $selected += @($items | Where-Object { $_.Service -eq $svc })
    }
}

$selectedKeys = @()
$unique = @()
foreach ($item in $selected) {
    $key = "$($item.Service):$($item.Name)"
    if ($selectedKeys -contains $key) { continue }
    $selectedKeys += $key
    $unique += $item
}
$selected = $unique

if ($selected.Count -eq 0) {
    throw "Nenhuma instância correspondente em $InstancesConf"
}

Write-Host "Vai APAGAR (não dá para desfazer):"
foreach ($item in $selected) {
    $key = "$($item.Service):$($item.Name)"
    Write-Host "  $key"
    Write-Host "    linha em $InstancesConf"
    foreach ($path in Get-InstanceArtifacts $item.Service $item.Name) {
        if (Test-Path -LiteralPath $path) {
            Write-Host "    $path"
        }
    }
}
Write-Host ""
Write-Host "NÃO será removido:"
Write-Host "  - Os apps originais e o perfil padrão"
Write-Host "  - Instâncias que não foram escolhidas"
Write-Host "  - Pastas isoladas que não estão no instances.conf"
Write-Host ""

if (-not $Yes) {
    $ans = Read-Host "Digite apagar para confirmar"
    if ($ans.Trim().ToLowerInvariant() -ne "apagar") {
        Write-Host "Cancelado."
        exit 0
    }
}

$lockDirs = @($selected | ForEach-Object { Join-Path (Get-ServiceInstancesBase $_.Service) $_.Name })
if (-not (Wait-ProfilesUnlocked -Dirs $lockDirs)) {
    Write-Host "Cancelado."
    exit 0
}

foreach ($item in $selected) {
    Remove-IsolatedInstance -Service $item.Service -Name $item.Name
}
Remove-InstanceKeysFromConf -Keys $selectedKeys

Write-Host ""
Write-Host "Pronto. As instâncias escolhidas saíram do disco e de $InstancesConf."
