# Entrada única no Windows. No macOS/Linux use ./setup

$ErrorActionPreference = "Stop"
$Scripts = $PSScriptRoot
$Root = Split-Path -Parent $Scripts
. (Join-Path $Scripts "lib\common.ps1")

$env:SKIP_IMPORT = "1"
$env:SETUP_QUIET = "1"

function Ask-Menu {
    param([string]$Prompt)
    $ans = (Read-Host $Prompt).Trim()
    Write-Host "----------"
    return $ans
}

function Choose-Filter {
    Write-Host "Quais apps nesta rodada?"
    Write-Host "  1) Claude  (app Desktop)"
    Write-Host "  2) Cursor  (IDE)"
    Write-Host "  3) Codex   (CLI no Terminal)"
    Write-Host "  4) Todos"
    switch (Ask-Menu "Escolha") {
        "1" { return "claude" }
        "2" { return "cursor" }
        "3" { return "codex" }
        "4" { return "" }
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
        Write-Host "Não há contas deste app na lista. Acrescente uma no passo anterior ou edite $InstancesConf."
        return
    }

    $guiServices = @()
    switch ($filter) {
        "claude" { $guiServices = @("claude") }
        "cursor" { $guiServices = @("cursor") }
        "codex" { $guiServices = @() }
        default { $guiServices = @("claude", "cursor") }
    }

    if ($guiServices.Count -gt 0) {
        Write-Host "Onde criar os atalhos das instâncias isoladas?"
        Write-Host "  1) Menu Iniciar"
        Write-Host "  2) Área de Trabalho"
        Write-Host "  3) Só pastas, sem atalho"
        $where = Ask-Menu "Escolha [1]"
        if (-not $where) { $where = "1" }
        switch ($where) {
            "1" {
                $dir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
                foreach ($svc in $guiServices) {
                    if (@(Get-ConfKeys -Filter $svc).Count -eq 0) { continue }
                    Invoke-WindowsLaunchers -Filter $svc -LauncherDir $dir
                }
            }
            "2" {
                foreach ($svc in $guiServices) {
                    if (@(Get-ConfKeys -Filter $svc).Count -eq 0) { continue }
                    Invoke-WindowsLaunchers -Filter $svc -LauncherDir (Join-Path $env:USERPROFILE "Desktop")
                }
            }
            "3" {
                foreach ($svc in $guiServices) {
                    $svcItems = @(Get-Instances -Filter $svc)
                    foreach ($instance in $svcItems) {
                        Initialize-InstanceDir $instance.Service (Join-Path (Get-ServiceInstancesBase $instance.Service) $instance.Name)
                    }
                }
            }
            default { throw "Opção inválida." }
        }

        $keep = @()
        if ($where -eq "2") {
            $keep = $guiServices
        }
        Remove-OurDesktopLaunchers -KeepServices $keep
    } else {
        Remove-OurDesktopLaunchers -KeepServices @("claude", "cursor")
    }

    if ((-not $filter -or $filter -eq "codex") -and @(Get-ConfKeys -Filter "codex").Count -gt 0) {
        $codexItems = @(Get-Instances -Filter "codex")
        foreach ($instance in $codexItems) {
            Initialize-InstanceDir $instance.Service (Join-Path (Get-ServiceInstancesBase $instance.Service) $instance.Name)
        }
        Remove-StaleCodexShims
        Ensure-CodexUserBinOnPath
        Write-CodexTerminalCommands
    }

    Remove-Item Env:SKIP_IMPORT -ErrorAction SilentlyContinue
    $names = @(Get-Instances -Filter $filter)
    $services = @($names.Service | Select-Object -Unique)
    foreach ($svc in $services) {
        $svcNames = @($names | Where-Object { $_.Service -eq $svc } | ForEach-Object { $_.Name })
        Prompt-AndImportDefaultData -Service $svc -Names $svcNames
    }
}

Write-Host "O que você quer fazer?"
Write-Host "  1) Configurar Nova Instancia  (recomendado, pastas e logins que já existem não são apagados)"
Write-Host "  2) Apagar Instância (exige confirmação)"
Write-Host "  3) Sair"

$action = Ask-Menu "Escolha [1]"
if (-not $action) { $action = "1" }

switch ($action) {
    "1" { Invoke-Configure }
    "2" {
        Prompt-AndRemoveInstances
    }
    { $_ -in @("3", "q", "Q") } { return }
    default { throw "Opção inválida." }
}
