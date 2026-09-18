$LibDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent (Split-Path -Parent $LibDir)
if (-not $env:INSTANCES_CONF) {
    $InstancesConf = Join-Path $RepoRoot "instances.conf"
} else {
    $InstancesConf = $env:INSTANCES_CONF
}

function Confirm-Service {
    param([string]$Service)
    switch ($Service) {
        "claude" { return }
        "cursor" { return }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-ServiceLabel {
    param([string]$Service)
    switch ($Service) {
        "claude" { return "Claude" }
        "cursor" { return "Cursor" }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-ServiceInstancesBase {
    param([string]$Service)
    switch ($Service) {
        "claude" { return Join-Path $env:USERPROFILE ".claude-instances" }
        "cursor" { return Join-Path $env:USERPROFILE ".cursor-instances" }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-DefaultTitle {
    param([string]$Service, [string]$Name)
    $pretty = $Name.Substring(0, 1).ToUpper() + $Name.Substring(1)
    return "$(Get-ServiceLabel $Service) ($pretty)"
}

function Get-DefaultIcon {
    param([string]$Service, [string]$Name)
    switch ($Name) {
        "personal" { return "🏠" }
        "home" { return "🏠" }
        "work" { return "💼" }
        "empresa" { return "💼" }
        "freela" { return "🛠️" }
        "freelance" { return "🛠️" }
        default {
            switch ($Service) {
                "claude" { return "🤖" }
                "cursor" { return "💻" }
                default { throw "Serviço desconhecido: $Service" }
            }
        }
    }
}

function Get-WindowsAppPath {
    param([string]$Service)
    switch ($Service) {
        "claude" {
            $path = Join-Path $env:LOCALAPPDATA "Programs\Claude\Claude.exe"
            if (Test-Path $path) { return $path }
            return $null
        }
        "cursor" {
            $candidates = @(
                (Join-Path $env:LOCALAPPDATA "Programs\cursor\Cursor.exe"),
                (Join-Path $env:LOCALAPPDATA "Programs\Cursor\Cursor.exe")
            )
            foreach ($candidate in $candidates) {
                if (Test-Path $candidate) { return $candidate }
            }
            return $null
        }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-WindowsLaunchArgs {
    param([string]$Service, [string]$InstanceDir)
    switch ($Service) {
        "claude" { return "--user-data-dir=`"$InstanceDir`"" }
        "cursor" {
            $extensionsDir = Join-Path $InstanceDir "extensions"
            return "--user-data-dir=`"$InstanceDir`" --extensions-dir=`"$extensionsDir`""
        }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Initialize-InstanceDir {
    param([string]$Service, [string]$InstanceDir)
    New-Item -ItemType Directory -Path $InstanceDir -Force | Out-Null
    switch ($Service) {
        "claude" { return }
        "cursor" {
            New-Item -ItemType Directory -Path (Join-Path $InstanceDir "extensions") -Force | Out-Null
        }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-DesktopDirs {
    @(
        (Join-Path $env:USERPROFILE "Desktop"),
        [Environment]::GetFolderPath("Desktop")
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
}

function Get-Instances {
    param([string]$Filter = "")

    if (-not (Test-Path $InstancesConf)) {
        throw "Não encontrei $InstancesConf"
    }
    if ($Filter) {
        Confirm-Service $Filter
    }

    $items = @()
    $seen = @{}
    $lines = Get-Content -Path $InstancesConf -Encoding UTF8

    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        $extras = $null
        if ($line.Contains("|")) {
            $idx = $line.IndexOf("|")
            $serviceAndName = $line.Substring(0, $idx).Trim()
            $extras = $line.Substring($idx + 1)
        } else {
            $serviceAndName = $line
        }

        if (-not $serviceAndName.Contains(":")) {
            throw "Linha inválida em $InstancesConf`: $line`nUse: serviço:nome"
        }

        $splitAt = $serviceAndName.IndexOf(":")
        $service = $serviceAndName.Substring(0, $splitAt).Trim()
        $name = $serviceAndName.Substring($splitAt + 1).Trim()
        Confirm-Service $service

        if (-not $name -or $name -notmatch '^[A-Za-z0-9._-]+$') {
            throw "Nome de instância inválido: '$name'"
        }
        if ($Filter -and $service -ne $Filter) {
            continue
        }

        $key = "$service:$name"
        if ($seen.ContainsKey($key)) {
            Write-Host "Ignorando duplicata em $InstancesConf`: $key"
            continue
        }
        $seen[$key] = $true

        $title = ""
        $icon = ""
        if ($extras) {
            $parts = $extras.Split("|")
            if ($parts.Length -ge 1) { $title = $parts[0].Trim() }
            if ($parts.Length -ge 2) { $icon = $parts[1].Trim() }
        }
        if (-not $title) { $title = Get-DefaultTitle $service $name }
        if (-not $icon) { $icon = Get-DefaultIcon $service $name }

        $items += [pscustomobject]@{
            Service = $service
            Name    = $name
            Title   = $title
            Icon    = $icon
        }
    }

    if ($items.Count -eq 0) {
        if ($Filter) {
            throw "Nenhuma instância de '$Filter' em $InstancesConf"
        }
        throw "Nenhuma instância em $InstancesConf"
    }

    return $items
}

function Get-LauncherInstanceName {
    param([string]$FileName, [string]$Label)
    $name = $FileName
    if ($name.StartsWith("$Label (")) {
        $name = $name.Substring($Label.Length + 2)
    }
    foreach ($ext in @(".lnk", ".command", ".desktop")) {
        if ($name.EndsWith($ext)) {
            $name = $name.Substring(0, $name.Length - $ext.Length)
        }
    }
    if ($name.EndsWith(")")) {
        $name = $name.Substring(0, $name.Length - 1)
    }
    return $name
}

function Test-PositiveInt {
    param([string]$Value)
    return [bool]($Value -match '^[1-9][0-9]*$')
}

function Get-NumberedPick {
    param(
        [string]$Answer,
        [int]$Count
    )
    $allN = $Count + 1
    $skipN = $Count + 2
    $answer = if ($null -eq $Answer) { "" } else { $Answer.Trim() -replace '[;,]', ' ' }
    if (-not $answer -or $answer -match '^(n|nao|não|cancelar|q)$') {
        return , @()
    }

    $tokens = @($answer -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -eq 1) {
        if (-not (Test-PositiveInt $tokens[0])) {
            throw "Opção inválida: $($tokens[0])"
        }
        $n = [int]$tokens[0]
        if ($n -eq $skipN) { return , @() }
        if ($n -eq $allN) { return , @("__ALL__") }
        if ($n -ge 1 -and $n -le $Count) { return , @($n - 1) }
        throw "Opção inválida: $n"
    }

    $picked = @()
    foreach ($token in $tokens) {
        if (-not (Test-PositiveInt $token)) {
            throw "Opção inválida: $token"
        }
        $n = [int]$token
        if ($n -lt 1 -or $n -gt $Count) {
            throw "Opção inválida: $token"
        }
        $idx = $n - 1
        if ($picked -notcontains $idx) {
            $picked += $idx
        }
    }
    return , @($picked)
}

function Get-InstanceDisplayName {
    param([string]$Service, [string]$Name)
    return "$(Get-ServiceLabel $Service) ($Name)"
}

function Get-InstanceArtifacts {
    param([string]$Service, [string]$Name)
    $display = Get-InstanceDisplayName $Service $Name
    $paths = @()
    $paths += Join-Path (Get-ServiceInstancesBase $Service) $Name
    foreach ($dir in Get-DesktopDirs) {
        $paths += Join-Path $dir "$display.lnk"
    }
    $start = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $paths += Join-Path $start "$display.lnk"
    return $paths
}

function Remove-IsolatedInstance {
    param([string]$Service, [string]$Name)
    Confirm-Service $Service
    if ($Name -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Nome de instância inválido: '$Name'"
    }
    $base = Get-ServiceInstancesBase $Service
    $dest = Join-Path $base $Name
    if ($dest -eq $base -or $dest -eq $env:USERPROFILE) {
        throw "Recusa apagar $dest"
    }
    foreach ($path in Get-InstanceArtifacts $Service $Name) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
            Write-Host "Removido: $path"
        }
    }
}

function Remove-InstanceKeysFromConf {
    param([string[]]$Keys)
    if (-not $Keys -or $Keys.Count -eq 0) { return }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($raw in Get-Content -Path $InstancesConf) {
        $keep = $true
        $line = $raw.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains(":")) {
            $serviceAndName = $line
            if ($line.Contains("|")) {
                $serviceAndName = $line.Substring(0, $line.IndexOf("|")).Trim()
            }
            $splitAt = $serviceAndName.IndexOf(":")
            if ($splitAt -ge 0) {
                $service = $serviceAndName.Substring(0, $splitAt).Trim()
                $name = $serviceAndName.Substring($splitAt + 1).Trim()
                if ($Keys -contains "$service`:$name") {
                    $keep = $false
                }
            }
        }
        if ($keep) { $out.Add($raw) }
    }
    $out | Set-Content -Path $InstancesConf -Encoding UTF8
}

function Get-ConfKeys {
    param([string]$Filter = "")
    if (-not (Test-Path $InstancesConf)) { return @() }
    $keys = @()
    foreach ($raw in Get-Content -Path $InstancesConf -Encoding UTF8) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains(":")) { continue }
        $serviceAndName = $line
        if ($line.Contains("|")) {
            $serviceAndName = $line.Substring(0, $line.IndexOf("|")).Trim()
        }
        $splitAt = $serviceAndName.IndexOf(":")
        if ($splitAt -lt 0) { continue }
        $service = $serviceAndName.Substring(0, $splitAt).Trim()
        $name = $serviceAndName.Substring($splitAt + 1).Trim()
        if ($Filter -and $service -ne $Filter) { continue }
        $keys += "$service`:$name"
    }
    return $keys
}

function Add-InstanceToConf {
    param([string]$Service, [string]$Name)
    Confirm-Service $Service
    if (-not $Name -or $Name -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Nome inválido: '$Name' (use letras, números, . _ -)"
    }
    $key = "$Service`:$Name"
    if (@(Get-ConfKeys) -contains $key) {
        throw "Já existe $key em $InstancesConf"
    }
    Add-Content -Path $InstancesConf -Value $key -Encoding UTF8
}

function Write-ConfInstances {
    param([string]$Filter = "")
    Write-Host "Contas em $InstancesConf`:"
    $keys = @(Get-ConfKeys -Filter $Filter)
    if ($keys.Count -eq 0) {
        if ($Filter) {
            Write-Host "  (nenhuma de $(Get-ServiceLabel $Filter))"
        } else {
            Write-Host "  (nenhuma)"
        }
        return
    }
    for ($i = 0; $i -lt $keys.Count; $i++) {
        Write-Host "  $($i + 1)) $($keys[$i])"
    }
}

function Prompt-AndAddInstances {
    param([string]$Filter = "")

    while ($true) {
        Write-Host ""
        Write-ConfInstances -Filter $Filter
        Write-Host ""
        Write-Host "  1) Adicionar instância"
        Write-Host "  2) Seguir"
        $ans = Read-Host "Escolha [2]"
        if (-not $ans -or $ans -eq "2") { return }
        if ($ans -ne "1") {
            Write-Host "Opção inválida."
            continue
        }

        $service = $Filter
        if (-not $service) {
            Write-Host ""
            Write-Host "  1) Claude"
            Write-Host "  2) Cursor"
            switch (Read-Host "App") {
                "1" { $service = "claude" }
                "2" { $service = "cursor" }
                default {
                    Write-Host "Opção inválida."
                    continue
                }
            }
        } else {
            Write-Host "App: $(Get-ServiceLabel $service)"
        }

        $name = (Read-Host "Nome da instância (ex: work, freela)").Trim()
        try {
            Add-InstanceToConf -Service $service -Name $name
        } catch {
            Write-Host $_
            continue
        }
        $dest = Join-Path (Get-ServiceInstancesBase $service) $name
        Write-Host "Adicionado ${service}:$name"
        Write-Host "  conf: $InstancesConf"
        Write-Host "  pasta (no configurar): $dest"
    }
}

. (Join-Path $PSScriptRoot "import.ps1")

function Prompt-AndRemoveInstances {
    param([switch]$Yes)

    $items = @(Get-Instances)
    $count = $items.Count
    $allN = $count + 1
    $skipN = $count + 2

    Write-Host ""
    Write-Host "Quais instâncias apagar? (lista de $InstancesConf)"
    for ($i = 0; $i -lt $count; $i++) {
        $item = $items[$i]
        $dest = Join-Path (Get-ServiceInstancesBase $item.Service) $item.Name
        $key = "$($item.Service):$($item.Name)"
        if (Test-Path -LiteralPath $dest) {
            Write-Host "  $($i + 1)) $key"
            Write-Host "      $dest"
        } else {
            Write-Host "  $($i + 1)) $key  (pasta ainda não existe)"
        }
    }
    Write-Host "  $allN) Todas as acima"
    Write-Host "  $skipN) Cancelar"
    Write-Host "Várias: 1,3"

    try {
        $picked = @(Get-NumberedPick -Answer (Read-Host "Escolha [$skipN]") -Count $count)
    } catch {
        Write-Host $_
        Write-Host "Cancelado."
        return
    }

    if ($picked.Count -eq 0) {
        Write-Host "Cancelado."
        return
    }

    $selected = @()
    if ($picked.Count -eq 1 -and $picked[0] -eq "__ALL__") {
        $selected = @($items)
    } else {
        foreach ($idx in $picked) {
            $selected += $items[$idx]
        }
    }

    $selectedKeys = @($selected | ForEach-Object { "$($_.Service):$($_.Name)" })
    $kept = @($items | Where-Object { $selectedKeys -notcontains "$($_.Service):$($_.Name)" })

    Write-Host ""
    Write-Host "Vai APAGAR (não dá para desfazer):"
    foreach ($item in $selected) {
        $key = "$($item.Service):$($item.Name)"
        Write-Host "  $key"
        Write-Host "    linha em $InstancesConf"
        $any = $false
        foreach ($path in Get-InstanceArtifacts $item.Service $item.Name) {
            if (Test-Path -LiteralPath $path) {
                Write-Host "    $path"
                $any = $true
            }
        }
        if (-not $any) {
            Write-Host "    (nada no disco além da linha do conf)"
        }
    }
    Write-Host ""
    Write-Host "Ficam intactos:"
    if ($kept.Count -gt 0) {
        foreach ($item in $kept) {
            Write-Host "  $($item.Service):$($item.Name)"
        }
    } else {
        Write-Host "  (nenhuma outra instância do conf)"
    }
    Write-Host "  perfil padrão / app original"
    Write-Host ""

    if (-not $Yes) {
        $ans = Read-Host "Digite apagar para confirmar"
        if ($ans.Trim().ToLowerInvariant() -ne "apagar") {
            Write-Host "Cancelado."
            return
        }
    }

    $lockDirs = @($selected | ForEach-Object { Join-Path (Get-ServiceInstancesBase $_.Service) $_.Name })
    if (-not (Wait-ProfilesUnlocked -Dirs $lockDirs)) {
        Write-Host "Cancelado."
        return
    }

    foreach ($item in $selected) {
        Remove-IsolatedInstance -Service $item.Service -Name $item.Name
    }
    Remove-InstanceKeysFromConf -Keys $selectedKeys
    Write-Host ""
    Write-Host "Pronto. As instâncias escolhidas saíram do disco e de $InstancesConf."
}
