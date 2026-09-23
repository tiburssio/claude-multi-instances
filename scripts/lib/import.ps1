function Get-DefaultUserDataDir {
    param([string]$Service)
    switch ($Service) {
        "claude" { return Join-Path $env:APPDATA "Claude" }
        "cursor" { return Join-Path $env:APPDATA "Cursor" }
        "codex" { return Join-Path $env:USERPROFILE ".codex" }
        default { throw "Serviço desconhecido: $Service" }
    }
}

function Get-DefaultExtensionsDir {
    param([string]$Service)
    switch ($Service) {
        "cursor" { return Join-Path $env:USERPROFILE ".cursor\extensions" }
        "claude" { return $null }
        "codex" { return $null }
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
        (Join-Path $Dir "IndexedDB"),
        (Join-Path $Dir "config.toml"),
        (Join-Path $Dir "auth.json"),
        (Join-Path $Dir "history.jsonl"),
        (Join-Path $Dir "sessions")
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
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludeFiles = @()
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $excludeDirs = @(
        "Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache",
        "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "Crashpad", "logs"
    )
    $excludeFileList = @("SingletonLock", "SingletonSocket", "SingletonCookie")
    if ($ExcludeFiles) {
        $excludeFileList += $ExcludeFiles
    }
    $args = @(
        $Source, $Destination, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np",
        "/XD"
    ) + $excludeDirs + @("/XF") + $excludeFileList
    & robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Falha ao copiar $Source → $Destination (robocopy $LASTEXITCODE)"
    }
}

function Import-DefaultToInstance {
    param([string]$Service, [string]$Name)
    $src = Get-DefaultUserDataDir $Service
    $dest = Join-Path (Get-ServiceInstancesBase $Service) $Name
    if ($env:SETUP_QUIET -ne "1") {
        Write-Host "Copiando perfil padrão → ${Service}:$Name"
        Write-Host "  de: $src"
        Write-Host "  para: $dest"
    }
    Initialize-InstanceDir $Service $dest
    if ($Service -eq "codex") {
        Copy-Profile $src $dest -ExcludeFiles @("auth.json")
        if ($env:SETUP_QUIET -ne "1") {
            Write-Host "  auth.json não copiado (refresh OAuth é de uso único)."
            Write-Host "  Nesta instância: $(Get-CodexShimName $Name) login"
            Write-Host "  Não use ~/.codex e esta pasta ao mesmo tempo com o mesmo login."
        }
    } else {
        Copy-Profile $src $dest
    }
    $extSrc = Get-DefaultExtensionsDir $Service
    if ($extSrc -and (Test-Path $extSrc)) {
        $extDest = Join-Path $dest "extensions"
        New-Item -ItemType Directory -Path $extDest -Force | Out-Null
        if ($env:SETUP_QUIET -ne "1") {
            Write-Host "  extensões: $extSrc → $extDest"
        }
        Copy-Profile $extSrc $extDest
    }
    if ($env:SETUP_QUIET -ne "1") {
        Write-Host "Pronto: ${Service}:$Name"
    }
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

    $empty = @()
    foreach ($name in $Names) {
        if (-not (Test-InstanceHasProfileData (Get-InstanceDir $Service $name))) {
            $empty += $name
        }
    }
    if ($empty.Count -eq 0) { return }

    $src = Get-DefaultUserDataDir $Service
    if (-not (Test-Path $src)) {
        return
    }

    $destNames = @()
    foreach ($name in $empty) {
        $ans = (Read-Host "Copiar perfil original do $(Get-ServiceLabel $Service) para $name? [y/N]").Trim()
        Write-Host "----------"
        if ($ans -match '^[yYsS]') {
            $destNames += $name
        }
    }

    if ($destNames.Count -eq 0) { return }

    $lockDirs = @(Get-DefaultUserDataDir $Service)
    foreach ($name in $destNames) {
        $lockDirs += Get-InstanceDir $Service $name
    }
    if (-not (Wait-ProfilesUnlocked -Dirs $lockDirs)) {
        Write-Host "Cópia do $(Get-ServiceLabel $Service) cancelada."
        return
    }

    foreach ($name in $destNames) {
        Import-DefaultToInstance -Service $Service -Name $name
    }
}
