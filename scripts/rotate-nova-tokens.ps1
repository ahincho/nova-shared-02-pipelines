#Requires -Version 5.1
<#
.SYNOPSIS
  Rota y limpia tokens de GitHub en los repos de Nova (cuenta personal ahincho).

.DESCRIPTION
  Automatiza 3 operaciones independientes sobre los secrets de GitHub de la cuenta
  personal ahincho. Pensado para ejecutarse desde una maquina con `gh` CLI autenticada.

  Fases (cada una se puede ejecutar por separado):
    propagate-read     Configura NOVA_PACKAGES_READ_TOKEN en los 7 repos B/C/D.
    purge-pat          BORRA NOVA_RELEASE_PAT de los 7 repos B/C/D (era residual, ya no
                       se usa tras la migracion a workflow_run + GITHUB_TOKEN puro).
                       No requiere valor de PAT: solo borra el secret.
    cleanup-residual   Borra NOVA_RELEASE_PAT residual de nova-shared-02-pipelines, spring-boot-parent
                       y los 3 repos demo.

  Seguridad:
    * El script NUNCA contiene valores de tokens. Solo acepta env vars o prompt interactivo.
    * En la fase propagate-read, pasa el valor a `gh secret set` por stdin para que
      no aparezca en el process listing ni en transcript de shell.
    * Las fases purge-pat y cleanup-residual NO requieren tokens (solo borran secrets).

.PARAMETER Phase
  Una de: propagate-read, purge-pat, cleanup-residual, all.

.PARAMETER DryRun
  Solo muestra las acciones que realizaria sin ejecutarlas.

.PARAMETER Force
  Omite la confirmacion interactiva antes de cada fase.

.ENVIRONMENT VARIABLES
  NOVA_PACKAGES_READ_TOKEN   Token de solo lectura para consumir releases de otros repos.
                             Solo necesario para la fase propagate-read.

.EXAMPLE
  # 1. Propagar READ (si no se hizo antes)
  $env:NOVA_PACKAGES_READ_TOKEN = '<token-de-read>'
  powershell -File scripts/rotate-nova-tokens.ps1 -Phase propagate-read

.EXAMPLE
  # 2. Borrar NOVA_RELEASE_PAT residual de los 7 repos B/C/D (no requiere PAT nuevo)
  powershell -File scripts/rotate-nova-tokens.ps1 -Phase purge-pat

.EXAMPLE
  # 3. Borrar PAT residual de los 5 repos que no lo usan
  powershell -File scripts/rotate-nova-tokens.ps1 -Phase cleanup-residual

.EXAMPLE
  # Previsualizar todas las acciones sin ejecutarlas
  powershell -File scripts/rotate-nova-tokens.ps1 -Phase all -DryRun

.NOTES
  Compatible con Windows PowerShell 5.1+ y PowerShell 7+.
  Si tu execution policy lo bloquea: powershell -ExecutionPolicy Bypass -File ...
#>

[CmdletBinding()]
param(
  [Parameter()]
  [ValidateSet('propagate-read', 'purge-pat', 'cleanup-residual', 'all')]
  [string]$Phase = 'all',

  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ============================================================
# Configuracion
# ============================================================
$Owner = 'ahincho'

# 7 repos B/C/D que necesitan READ + PAT conservado
$ReposBCDE = @(
  'nova-java-08-commons-spring-boot-starter'
  'nova-java-09-observability-spring-boot-starter'
  'nova-java-12-spring-boot-starter'
  'nova-java-notifications-micronaut-module'
  'nova-java-notifications-quarkus-extension'
  'nova-java-notifications-spring-boot-starter'
  'nova-java-notifications'
)

# 5 repos con PAT residual sin consumer real
#   * 2 repos base (parent POM + devops): no publican nada
#   * 3 repos demo de Nova Notifications: creados 2026-07-15 sin workflows
#   * nova-java-19-quarkus-template: sin workflows (recien agregado 2026-07-15)
# NO incluye nova-java-07-architecture-rules: ese SI usa NOVA_RELEASE_PAT
# activamente en ci.yml para resolver packages cross-repo con Maven.
$ReposResidual = @(
  'nova-shared-02-pipelines'
  'nova-java-14-spring-boot-parent'
  'demo-notifications-micronaut'
  'demo-notifications-quarkus'
  'demo-notifications-spring-boot'
  'nova-java-19-quarkus-template'
)

# ============================================================
# Helpers
# ============================================================
function Write-Banner {
  param([string]$Text)
  Write-Host ''
  Write-Host ('=' * 70) -ForegroundColor Cyan
  Write-Host ("  {0}" -f $Text) -ForegroundColor Cyan
  Write-Host ('=' * 70) -ForegroundColor Cyan
}

function Write-Info {
  param([string]$Text)
  Write-Host "[i] $Text" -ForegroundColor Cyan
}

function Write-Ok {
  param([string]$Text)
  Write-Host "[+] $Text" -ForegroundColor Green
}

function Write-Warn {
  param([string]$Text)
  Write-Host "[!] $Text" -ForegroundColor Yellow
}

function Write-Err {
  param([string]$Text)
  Write-Host "[x] $Text" -ForegroundColor Red
}

function Confirm-Continue {
  param([string]$Message)
  if ($Force) { return }
  Write-Host ''
  $resp = Read-Host "$Message [y/N]"
  if ($resp -ne 'y') {
    Write-Warn 'Operacion cancelada por el usuario.'
    exit 0
  }
}

function Get-SecretValue {
  param([string]$EnvVarName)
  $existing = [Environment]::GetEnvironmentVariable($EnvVarName)
  if (-not [string]::IsNullOrWhiteSpace($existing)) {
    return $existing
  }
  Write-Host ''
  Write-Info "La variable de entorno '$EnvVarName' no esta definida."
  Write-Info 'Se solicitara interactivamente (la entrada quedara oculta).'
  Write-Host ''
  $secure = Read-Host "Pegar valor para $EnvVarName" -AsSecureString
  if ($null -eq $secure -or $secure.Length -eq 0) {
    throw "No se ingreso ningun valor para $EnvVarName."
  }
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
  }
  finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
  }
}

function Set-Secret {
  param(
    [string]$Repo,
    [string]$SecretName,
    [string]$SecretValue
  )
  $target = "$Owner/$Repo"
  if ($DryRun) {
    Write-Host "  [DRY-RUN] gh secret set $SecretName --repo $target (valor oculto)" -ForegroundColor Yellow
    return
  }
  Write-Host "  -> $target : $SecretName = *** (longitud $($SecretValue.Length))" -ForegroundColor Green
  $SecretValue | gh secret set $SecretName --repo $target 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Fall\u00f3 gh secret set en $target (exit code $LASTEXITCODE)."
  }
  Write-Ok "OK $target"
}

function Remove-Secret {
  param(
    [string]$Repo,
    [string]$SecretName
  )
  $target = "$Owner/$Repo"
  if ($DryRun) {
    Write-Host "  [DRY-RUN] gh secret delete $SecretName --repo $target" -ForegroundColor Yellow
    return
  }
  # Check first if the secret exists (idempotent + skip on 404)
  $existing = gh secret list -R $target 2>&1 | Where-Object { $_ -match "^$SecretName\s" }
  if (-not $existing) {
    Write-Host "  -> $target : $SecretName no existe, saltando" -ForegroundColor Yellow
    return
  }
  Write-Host "  -> $target : eliminando $SecretName" -ForegroundColor Green
  gh secret delete $SecretName -R $target 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Fall\u00f3 gh secret delete en $target (exit code $LASTEXITCODE)."
  }
  Write-Ok "OK $target"
}

function Test-GhCli {
  $ver = gh --version 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "gh CLI no esta instalado o no esta en PATH."
  }
  $auth = gh auth status 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "gh CLI no esta autenticada. Ejecuta 'gh auth login' primero."
  }
  Write-Info "gh CLI OK"
}

# ============================================================
# Fases
# ============================================================
function Invoke-PropagateRead {
  [CmdletBinding()]
  param()

  Write-Banner 'Fase 1: propagate NOVA_PACKAGES_READ_TOKEN'
  Write-Info "Repos objetivo ($($ReposBCDE.Count)):"
  foreach ($r in $ReposBCDE) {
    Write-Host "    - $Owner/$r"
  }

  $value = Get-SecretValue -EnvVarName 'NOVA_PACKAGES_READ_TOKEN'
  if ($value.Length -lt 10) {
    throw "NOVA_PACKAGES_READ_TOKEN parece demasiado corto (longitud=$($value.Length))."
  }

  Confirm-Continue "Configurar NOVA_PACKAGES_READ_TOKEN en $($ReposBCDE.Count) repos?"

  foreach ($r in $ReposBCDE) {
    Set-Secret -Repo $r -SecretName 'NOVA_PACKAGES_READ_TOKEN' -SecretValue $value
  }

  Write-Ok 'Fase 1 completa.'
  Write-Info 'Antes de Fase 2, valida un publish real en uno de estos repos.'
}

function Invoke-PurgePat {
  [CmdletBinding()]
  param()

  Write-Banner 'Fase 2: purge NOVA_RELEASE_PAT (7 repos B/C/D)'
  Write-Info "Repos objetivo ($($ReposBCDE.Count)):"
  foreach ($r in $ReposBCDE) {
    Write-Host "    - $Owner/$r"
  }
  Write-Warn 'Esta operacion BORRA el secret NOVA_RELEASE_PAT de cada repo.'
  Write-Warn 'No requiere valor nuevo: el secret ya no se usa en ningun workflow.'
  Write-Warn 'A partir de esta fase, publish se hace 100% con GITHUB_TOKEN.'

  Confirm-Continue "Borrar NOVA_RELEASE_PAT de $($ReposBCDE.Count) repos?"

  foreach ($r in $ReposBCDE) {
    Remove-Secret -Repo $r -SecretName 'NOVA_RELEASE_PAT'
  }

  Write-Ok 'Fase 2 completa.'
  Write-Info 'Despues de esta fase, tambien revoca el fine-grained token en la UI.'
}

function Invoke-CleanupResidual {
  [CmdletBinding()]
  param()

  Write-Banner 'Fase 3: cleanup residual NOVA_RELEASE_PAT'
  Write-Info "Repos objetivo ($($ReposResidual.Count)):"
  foreach ($r in $ReposResidual) {
    Write-Host "    - $Owner/$r"
  }
  Write-Info 'Estos repos tienen NOVA_RELEASE_PAT configurado pero ningun workflow lo usa.'

  Confirm-Continue "Borrar NOVA_RELEASE_PAT de $($ReposResidual.Count) repos?"

  foreach ($r in $ReposResidual) {
    Remove-Secret -Repo $r -SecretName 'NOVA_RELEASE_PAT'
  }

  Write-Ok 'Fase 3 completa.'
}

# ============================================================
# Main
# ============================================================
try {
  Test-GhCli

  switch ($Phase) {
    'propagate-read'   { Invoke-PropagateRead }
    'purge-pat'        { Invoke-PurgePat }
    'cleanup-residual' { Invoke-CleanupResidual }
    'all' {
      Invoke-PropagateRead
      Invoke-PurgePat
      Invoke-CleanupResidual
    }
  }

  Write-Host ''
  Write-Ok 'Script finalizado sin errores.'
}
catch {
  Write-Err $_.Exception.Message
  exit 1
}