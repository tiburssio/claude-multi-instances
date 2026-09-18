function Get-DefaultUserDataDir {
    param([string]$Service)
    switch ($Service) {
        "claude" { return Join-Path $env:APPDATA "Claude" }
        "cursor" { return Join-Path $env:APPDATA "Cursor" }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-DefaultExtensionsDir {
    param([string]$Service)
    switch ($Service) {
        "cursor" { return Join-Path $env:USERPROFILE ".cursor\extensions" }
        "claude" { return $null }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-InstanceDir {
    param([string]$Service, [string]$Name)
    return Join-Path (Get-ServiceInstancesBase $Service) $Name
}

function Test-InstanceHasProfileData {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        return $false
    }
    $markers = @(
        (Join-Path $Dir "Cookies"),
        (Join-Path $Dir "config.json"),
        (Join-Path $Dir "claude_desktop_config.json"),
        (Join-Path $Dir "User\settings.json"),
        (Join-Path $Dir "User"),
        (Join-Path $Dir "vm_bundles"),
        (Join-Path $Dir "Local Storage"),
        (Join-Path $Dir "IndexedDB")
    )
    foreach ($path in $markers) {
        if (Test-Path -LiteralPath $path) {
            return $true
        }
    }
    return $false
}

function Confirm-OverwriteInstance {
    param([string]$Name)
    $ans = Read-Host "$Name já tem dados isolados. Sobrescrever com o perfil padrão? [y/N]"
    return ($ans -match '^[yYsS]')
}

function Test-ProfileLocked {
    param([string]$Dir)
    return (
        (Test-Path -LiteralPath (Join-Path $Dir "SingletonLock")) -or
        (Test-Path -LiteralPath (Join-Path $Dir "SingletonSocket"))
    )
}

function Wait-ProfilesUnlocked {
    param([string[]]$Dirs)
    while ($true) {
        $locked = @($Dirs | Where-Object { $_ -and (Test-ProfileLocked $_) })
        if ($locked.Count -eq 0) {
            return $true
        }
        Write-Host ""
        Write-Host "Feche o app que está usando estas pastas (lock file):"
        foreach ($dir in $locked) {
            Write-Host "  $dir"
        }
        $again = Read-Host "Enter para tentar de novo, n para cancelar"
        if ($again -match '^[nN]') {
            return $false
        }
    }
}

function Copy-Profile {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $excludeDirs = @(
        "Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache",
        "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "Crashpad", "logs"
    )
    $excludeFiles = @("SingletonLock", "SingletonSocket", "SingletonCookie")
    $args = @(
        $Source, $Destination, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np",
        "/XD"
    ) + $excludeDirs + @("/XF") + $excludeFiles
    & robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Falha ao copiar $Source → $Destination (robocopy $LASTEXITCODE)"
    }
}

function Import-DefaultToInstance {
    param([string]$Service, [string]$Name)
    $src = Get-DefaultUserDataDir $Service
    $dest = Join-Path (Get-ServiceInstancesBase $Service) $Name
    Write-Host "Copiando perfil padrão → ${Service}:$Name"
    Write-Host "  de: $src"
    Write-Host "  para: $dest"
    Initialize-InstanceDir $Service $dest
    Copy-Profile $src $dest
    $extSrc = Get-DefaultExtensionsDir $Service
    if ($extSrc -and (Test-Path $extSrc)) {
        $extDest = Join-Path $dest "extensions"
        New-Item -ItemType Directory -Path $extDest -Force | Out-Null
        Write-Host "  extensões: $extSrc → $extDest"
        Copy-Profile $extSrc $extDest
    }
    Write-Host "Pronto: ${Service}:$Name"
}

function Get-ImportSelection {
    param(
        [string]$Answer,
        [string[]]$Names
    )
    $picked = @(Get-NumberedPick -Answer $Answer -Count $Names.Count)
    if ($picked.Count -eq 0) { return , @() }
    if ($picked.Count -eq 1 -and $picked[0] -eq "__ALL__") { return , @("__ALL__") }
    $namesOut = @()
    foreach ($idx in $picked) {
        $namesOut += $Names[$idx]
    }
    return , @($namesOut)
}

function Prompt-AndImportDefaultData {
    param(
        [string]$Service,
        [string[]]$Names
    )

    if ($env:SKIP_IMPORT -eq "1") { return }
    if (-not [Environment]::UserInteractive) { return }
    if (-not $Names -or $Names.Count -eq 0) { return }

    $src = Get-DefaultUserDataDir $Service
    if (-not (Test-Path $src)) {
        Write-Host "Perfil padrão do $(Get-ServiceLabel $Service) não encontrado ($src). Pulando import."
        return
    }

    $count = $Names.Count
    $allN = $count + 1
    $skipN = $count + 2
    Write-Host ""
    Write-Host "Quer colocar os dados do $(Get-ServiceLabel $Service) padrão em:"
    for ($i = 0; $i -lt $count; $i++) {
        $name = $Names[$i]
        $dest = Get-InstanceDir $Service $name
        if (Test-InstanceHasProfileData $dest) {
            Write-Host "  $($i + 1)) Somente no $name  (já tem dados)"
        } else {
            Write-Host "  $($i + 1)) Somente no $name"
        }
    }
    Write-Host "  $allN) Todas as instâncias vazias (não mexe nas que já têm dados)"
    Write-Host "  $skipN) Não importar"
    Write-Host "Várias: 1,3"
    Write-Host ""
    Write-Host "O perfil original não é apagado. Setup nunca apaga pastas de instâncias existentes."
    $ans = Read-Host "Escolha [${skipN}]"

    try {
        $chosen = @(Get-ImportSelection -Answer $ans -Names $Names)
    } catch {
        Write-Host $_
        Write-Host "Import cancelado."
        return
    }

    if ($chosen.Count -eq 0) {
        Write-Host "Import do $(Get-ServiceLabel $Service) pulado."
        return
    }

    $destNames = @()
    if ($chosen.Count -eq 1 -and $chosen[0] -eq "__ALL__") {
        foreach ($name in $Names) {
            if (Test-InstanceHasProfileData (Get-InstanceDir $Service $name)) {
                Write-Host "Mantendo ${Service}:$name (já tem dados)."
                continue
            }
            $destNames += $name
        }
    } else {
        foreach ($name in $chosen) {
            if (Test-InstanceHasProfileData (Get-InstanceDir $Service $name)) {
                if (Confirm-OverwriteInstance $name) {
                    $destNames += $name
                } else {
                    Write-Host "Mantendo ${Service}:$name."
                }
                continue
            }
            $destNames += $name
        }
    }

    if ($destNames.Count -eq 0) {
        Write-Host "Nada para importar."
        return
    }

    $lockDirs = @(Get-DefaultUserDataDir $Service)
    foreach ($name in $destNames) {
        $lockDirs += Get-InstanceDir $Service $name
    }
    if (-not (Wait-ProfilesUnlocked -Dirs $lockDirs)) {
        Write-Host "Import do $(Get-ServiceLabel $Service) cancelado."
        return
    }

    foreach ($name in $destNames) {
        Import-DefaultToInstance -Service $Service -Name $name
    }
}
