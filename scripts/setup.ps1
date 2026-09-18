# Entrada única no Windows. No macOS/Linux use ./setup

$ErrorActionPreference = "Stop"
$Scripts = $PSScriptRoot
$Root = Split-Path -Parent $Scripts
. (Join-Path $Scripts "lib\common.ps1")

$env:SKIP_IMPORT = "1"

function Ask([string]$Prompt) {
    return (Read-Host $Prompt).Trim()
}

function Choose-Filter {
    Write-Host ""
    Write-Host "Quais apps configurar?"
    Write-Host "  1) Claude"
    Write-Host "  2) Cursor"
    Write-Host "  3) Ambos"
    switch (Ask "Escolha") {
        "1" { return "claude" }
        "2" { return "cursor" }
        "3" { return "" }
        default { throw "Opção inválida." }
    }
}

function Invoke-WindowsLaunchers {
    param([string]$Filter, [string]$LauncherDir)
    $env:LAUNCHER_DIR = $LauncherDir
    $file = Join-Path $Scripts "windows\setup-launchers.ps1"
    if ($Filter) {
        & $file -Service $Filter
    } else {
        & $file
    }
}

function Invoke-Configure {
    $filter = Choose-Filter
    Prompt-AndAddInstances -Filter $filter
    $confKeys = @(Get-ConfKeys -Filter $filter)
    if ($confKeys.Count -eq 0) {
        Write-Host "Nenhuma instância no conf para configurar. Use a opção 2 ou edite $InstancesConf."
        return
    }
    Write-Host ""
    Write-Host "Onde criar os atalhos?"
    Write-Host "  1) Menu Iniciar"
    Write-Host "  2) Área de Trabalho"
    Write-Host "  3) Só as pastas de dados, sem atalhos"
    $where = Ask "Escolha [1]"
    if (-not $where) { $where = "1" }
    $names = @(Get-Instances -Filter $filter)
    switch ($where) {
        "1" {
            $dir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
            Invoke-WindowsLaunchers -Filter $filter -LauncherDir $dir
        }
        "2" {
            Invoke-WindowsLaunchers -Filter $filter -LauncherDir (Join-Path $env:USERPROFILE "Desktop")
        }
        "3" {
            foreach ($instance in $names) {
                Initialize-InstanceDir $instance.Service (Join-Path (Get-ServiceInstancesBase $instance.Service) $instance.Name)
                Write-Host "Pasta pronta: $($instance.Service):$($instance.Name)"
            }
        }
        default { throw "Opção inválida." }
    }
    Write-Host ""
    Write-Host "Setup aditivo: pastas já existentes em ~/.claude-instances e ~/.cursor-instances não foram apagadas."
    Remove-Item Env:SKIP_IMPORT -ErrorAction SilentlyContinue
    $services = @($names.Service | Select-Object -Unique)
    foreach ($svc in $services) {
        $svcNames = @($names | Where-Object { $_.Service -eq $svc } | ForEach-Object { $_.Name })
        Prompt-AndImportDefaultData -Service $svc -Names $svcNames
    }
}

Write-Host "claude-multi-instances  (windows)"
Write-Host "Lista de contas: $InstancesConf"
Write-Host ""
Write-Host "O que você quer fazer?"
Write-Host "  1) Configurar instâncias"
Write-Host "  2) Adicionar instância"
Write-Host "  3) Importar dados do perfil padrão"
Write-Host "  4) Remover atalhos da Área de Trabalho (mantém os dados)"
Write-Host "  5) Apagar instâncias isoladas (irreversível: dados + atalhos)"
Write-Host "  6) Sair"

$action = Ask "Escolha [1]"
if (-not $action) { $action = "1" }

switch ($action) {
    "1" { Invoke-Configure }
    "2" {
        Prompt-AndAddInstances
        $go = Ask "Configurar atalhos agora? [Y/n]"
        if ($go -match '^[nN]') {
            Write-Host "Opção 1 cria os atalhos a partir do conf."
        } else {
            Invoke-Configure
        }
    }
    "3" {
        Remove-Item Env:SKIP_IMPORT -ErrorAction SilentlyContinue
        $filter = Choose-Filter
        $names = @(Get-Instances -Filter $filter)
        $services = @($names.Service | Select-Object -Unique)
        foreach ($svc in $services) {
            $svcNames = @($names | Where-Object { $_.Service -eq $svc } | ForEach-Object { $_.Name })
            Prompt-AndImportDefaultData -Service $svc -Names $svcNames
        }
    }
    "4" {
        foreach ($svc in @("claude", "cursor")) {
            $label = Get-ServiceLabel $svc
            foreach ($dir in Get-DesktopDirs) {
                Get-ChildItem -Path $dir -Filter "$label (*).lnk" -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Force
                    Write-Host "Removido: $($_.FullName)"
                }
            }
        }
        Write-Host "Atalhos da Área de Trabalho removidos. Dados isolados continuam intactos."
    }
    "5" {
        Prompt-AndRemoveInstances
    }
    { $_ -in @("6", "q", "Q") } { return }
    default { throw "Opção inválida." }
}
