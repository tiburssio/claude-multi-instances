# Cria atalhos .lnk na Área de Trabalho a partir de instances.conf.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/windows/setup-launchers.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/windows/setup-launchers.ps1 -Service claude

param(
    [ValidateSet("claude", "cursor", "codex")]
    [string]$Service
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\lib\common.ps1")
if ($env:SETUP_QUIET -eq "1") {
    function Write-Host { }
}

$instances = @(Get-Instances -Filter $Service)
if ($env:LAUNCHER_DIR) {
    $desktopDir = $env:LAUNCHER_DIR
} else {
    $desktopDir = Join-Path $env:USERPROFILE "Desktop"
}
if (-not (Test-Path $desktopDir)) {
    New-Item -ItemType Directory -Path $desktopDir -Force | Out-Null
}

$created = 0
$skipped = @{}
$createdServices = @{}
$appPaths = @{}

foreach ($instance in $instances) {
    if (-not $appPaths.ContainsKey($instance.Service)) {
        $resolved = Get-WindowsAppPath $instance.Service
        if (-not $resolved) {
            $skipped[$instance.Service] = "executável não encontrado"
            $appPaths[$instance.Service] = $null
            continue
        }
        $appPaths[$instance.Service] = $resolved
    }

    $appPath = $appPaths[$instance.Service]
    if (-not $appPath) {
        continue
    }

    $label = Get-ServiceLabel $instance.Service
    $instanceDir = Join-Path (Get-ServiceInstancesBase $instance.Service) $instance.Name
    Initialize-InstanceDir $instance.Service $instanceDir

    $shortcutPath = Join-Path $desktopDir "$label ($($instance.Name)).lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($instance.Service -eq "codex") {
        $shortcut.TargetPath = $env:ComSpec
        $shortcut.Arguments = "/k set `"CODEX_HOME=$instanceDir`" && `"$appPath`""
        $shortcut.WorkingDirectory = $instanceDir
    } else {
        $shortcut.TargetPath = $appPath
        $shortcut.Arguments = Get-WindowsLaunchArgs $instance.Service $instanceDir
        $shortcut.WorkingDirectory = Get-ServiceInstancesBase $instance.Service
    }
    $shortcut.Save()

    Write-Host "Criado: $shortcutPath -> dados em $instanceDir"
    $created++
    $createdServices[$instance.Service] = $true
}

if ($created -eq 0) {
    throw "Nenhum launcher criado. Verifique se o app está instalado."
}

foreach ($svc in @($createdServices.Keys)) {
    $label = Get-ServiceLabel $svc
    $keep = @($instances | Where-Object { $_.Service -eq $svc } | ForEach-Object { $_.Name })
    foreach ($dir in Get-DesktopDirs) {
        $launchers = Get-ChildItem -Path $dir -Filter "$label (*).lnk" -ErrorAction SilentlyContinue
        foreach ($launcher in $launchers) {
            $name = Get-LauncherInstanceName $launcher.Name $label
            if ($keep -notcontains $name) {
                Remove-Item -LiteralPath $launcher.FullName -Force
                Write-Host "Removido (não está em instances.conf): $($launcher.FullName)"
            }
        }
    }
}

Write-Host ""
Write-Host "Pronto. Na Área de Trabalho:"
foreach ($instance in $instances) {
    if ($createdServices.ContainsKey($instance.Service)) {
        Write-Host "  - $(Get-ServiceLabel $instance.Service) ($($instance.Name)).lnk"
    }
}

if ($skipped.Count -gt 0) {
    Write-Host ""
    Write-Host "Ignorados:"
    foreach ($svc in $skipped.Keys) {
        Write-Host "  $(Get-ServiceLabel $svc): $($skipped[$svc])"
    }
}

Write-Host ""
Write-Host "IMPORTANTE:"
Write-Host "- Feche todas as janelas do app antes de logar em uma instância nova."
Write-Host "- Logue uma conta por vez. Depois de logadas, podem ficar abertas juntas."
Write-Host "- Lista de contas: $InstancesConf"
if ($createdServices.ContainsKey("codex")) {
    Write-Host "- Codex: abre o cmd com CODEX_HOME na pasta da instância. Faça login em cada uma."
}

foreach ($svc in @($createdServices.Keys)) {
    $names = @($instances | Where-Object { $_.Service -eq $svc } | ForEach-Object { $_.Name })
    Prompt-AndImportDefaultData -Service $svc -Names $names
}
