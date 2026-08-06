# setup-windows-launchers.ps1
#
# Cria atalhos (.lnk) na Área de Trabalho do Windows para rodar múltiplas
# instâncias isoladas do Claude Desktop (uma por conta), cada uma com seu
# próprio --user-data-dir. Isso dá a cada instância um sandbox completo
# (config, VM do Cowork, MCPs, sessão, tokens de auth), então features
# como o Cowork funcionam normalmente em todas.
#
# Uso (execute no PowerShell como Administrador, ou ajuste a política):
#   powershell -ExecutionPolicy Bypass -File setup-windows-launchers.ps1
#
# Edite a lista $INSTANCE_NAMES abaixo para os nomes/quantidade de contas
# que você quer.

$APP_PATH = "C:\Users\$env:USERNAME\AppData\Local\Programs\Claude\Claude.exe"
$INSTANCES_BASE = "$env:USERPROFILE\.claude-instances"
$DESKTOP_DIR = "$env:USERPROFILE\Desktop"

$INSTANCE_NAMES = @("work", "personal")

if (-not (Test-Path $APP_PATH)) {
    Write-Host "Não encontrei Claude.exe em $APP_PATH"
    Write-Host "Verifique se Claude Desktop está instalado ou ajuste APP_PATH no script."
    exit 1
}

if (-not (Test-Path $INSTANCES_BASE)) {
    New-Item -ItemType Directory -Path $INSTANCES_BASE -Force | Out-Null
}

foreach ($name in $INSTANCE_NAMES) {
    $instance_dir = "$INSTANCES_BASE\$name"
    if (-not (Test-Path $instance_dir)) {
        New-Item -ItemType Directory -Path $instance_dir -Force | Out-Null
    }

    $shortcut_path = "$DESKTOP_DIR\Claude ($name).lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcut_path)
    $shortcut.TargetPath = $APP_PATH
    $shortcut.Arguments = "--user-data-dir=`"$instance_dir`""
    $shortcut.WorkingDirectory = $INSTANCES_BASE
    $shortcut.Save()

    Write-Host "Criado: $shortcut_path -> dados em $instance_dir"
}

Write-Host ""
Write-Host "Pronto. Na Área de Trabalho agora existem:"
foreach ($name in $INSTANCE_NAMES) {
    Write-Host "  - Claude ($name).lnk"
}
Write-Host ""
Write-Host "IMPORTANTE:"
Write-Host "1. Feche TODAS as janelas/instâncias do Claude antes de logar em uma nova."
Write-Host "2. Clique em 'Claude (work).lnk', faça login na conta da empresa,"
Write-Host "   espere o Cowork terminar de montar o ambiente (VM ~1-2GB na primeira vez)."
Write-Host "3. Feche essa instância, depois clique em 'Claude (personal).lnk' e logue na"
Write-Host "   conta pessoal. Cada uma tem seu próprio sandbox, então o Cowork deve"
Write-Host "   funcionar normalmente nas duas."
Write-Host "4. Depois de logado, pode abrir as duas ao mesmo tempo sem conflito."
