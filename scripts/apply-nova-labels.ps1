#Requires -Version 5.1
<#
.SYNOPSIS
  Aplica Esquema B de labels a los 32 repos Nova Platform + demos.

.DESCRIPTION
  Estandariza el esquema de labels:
    - Crea labels Scheme B por repo (type, lifecycle, framework, area, etc.).
    - Borra labels Scheme A (nova:semver, nova:docs, sprint-*, etc.).
    - Mantiene labels que ya son Scheme B y GitHub defaults.

  Idempotente: aplicar 2 veces da el mismo resultado.

.PARAMETER DryRun
  Solo muestra las acciones que realizaria sin ejecutarlas.

.PARAMETER Force
  Omite la confirmacion interactiva al inicio.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/apply-nova-labels.ps1 -DryRun

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/apply-nova-labels.ps1 -Force
#>

[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ============================================================
# Esquema B - Labels estandar (todos con color)
# ============================================================
$SchemeB = @(
  @{ Name = 'nova-platform';                 Color = '00add8'; Description = 'Belongs to Nova Platform meta-framework' }

  # Type
  @{ Name = 'type:library';       Color = '1d76db'; Description = 'Pure library' }
  @{ Name = 'type:extension';     Color = '6f42c1'; Description = 'Framework extension' }
  @{ Name = 'type:starter';       Color = '6f42c1'; Description = 'Spring Boot / Micronaut starter' }
  @{ Name = 'type:module';        Color = '6f42c1'; Description = 'Framework module' }
  @{ Name = 'type:archetype';     Color = '6f42c1'; Description = 'Maven archetype' }
  @{ Name = 'type:template';      Color = '6f42c1'; Description = 'Project template' }
  @{ Name = 'type:parent-pom';    Color = 'cccccc'; Description = 'Parent POM' }
  @{ Name = 'type:plugin';        Color = '6f42c1'; Description = 'Gradle plugin' }
  @{ Name = 'type:instance';      Color = '1d76db'; Description = 'Microservice instance' }
  @{ Name = 'type:meta-starter';  Color = '6f42c1'; Description = 'Meta-starter that bundles other starters' }
  @{ Name = 'type:demo';          Color = 'fbca04'; Description = 'Demo / example' }
  @{ Name = 'type:docs';          Color = 'cccccc'; Description = 'Documentation repository' }
  @{ Name = 'type:infra';         Color = 'cccccc'; Description = 'Infrastructure as code' }

  # Lifecycle
  @{ Name = 'lifecycle:stable';       Color = '0e8a16'; Description = 'Production-ready' }
  @{ Name = 'lifecycle:beta';         Color = 'fbca04'; Description = 'Usable but evolving' }
  @{ Name = 'lifecycle:experimental'; Color = 'd93f0b'; Description = 'Under development' }
  @{ Name = 'lifecycle:deprecated';   Color = 'cfd3d7'; Description = 'No longer maintained' }
  @{ Name = 'lifecycle:archived';     Color = '000000'; Description = 'Archived / read-only' }

  # Framework
  @{ Name = 'framework:java-pure';   Color = '1d76db'; Description = 'Pure Java (no framework)' }
  @{ Name = 'framework:spring-boot'; Color = '6db33f'; Description = 'Spring Boot' }
  @{ Name = 'framework:quarkus';     Color = '4695eb'; Description = 'Quarkus' }
  @{ Name = 'framework:micronaut';   Color = '4695eb'; Description = 'Micronaut' }
  @{ Name = 'framework:nestjs';      Color = 'e0234e'; Description = 'NestJS' }
  @{ Name = 'framework:gradle';      Color = '02303a'; Description = 'Built with Gradle' }
  @{ Name = 'framework:maven';       Color = '02303a'; Description = 'Built with Maven' }

  # Area
  @{ Name = 'area:api-standard';    Color = 'bfd4f2'; Description = 'API standards (ApiResponse, HATEOAS, etc.)' }
  @{ Name = 'area:notifications';   Color = 'bfd4f2'; Description = 'Notifications subsystem' }
  @{ Name = 'area:observability';   Color = 'bfd4f2'; Description = 'Observability (metrics, traces, logs)' }
  @{ Name = 'area:common';          Color = 'bfd4f2'; Description = 'Common utilities / shared infrastructure' }
  @{ Name = 'area:bom';             Color = 'bfd4f2'; Description = 'Bill of Materials / dependency management' }
  @{ Name = 'area:devops';          Color = 'bfd4f2'; Description = 'CI/CD and devops tooling' }
  @{ Name = 'area:infrastructure';  Color = 'bfd4f2'; Description = 'Infrastructure as code' }
  @{ Name = 'area:documentation';   Color = 'bfd4f2'; Description = 'Documentation' }

  # Priority
  @{ Name = 'priority:critical'; Color = 'b60205'; Description = 'Critical priority (block release)' }
  @{ Name = 'priority:high';     Color = 'd93f0b'; Description = 'High priority' }
  @{ Name = 'priority:medium';   Color = 'fbca04'; Description = 'Medium priority' }
  @{ Name = 'priority:low';      Color = 'cfd3d7'; Description = 'Low priority' }

  # Status / process
  @{ Name = 'breaking-change';     Color = 'd93f0b'; Description = 'Introduces a breaking change' }
  @{ Name = 'security';            Color = 'b60205'; Description = 'Security issue' }
  @{ Name = 'dependencies';        Color = '0366d6'; Description = 'Dependency update / bump' }
  @{ Name = 'autorelease: pending'; Color = 'ededed'; Description = 'Auto-release: PR open, waiting for merge' }
  @{ Name = 'autorelease: tagged';  Color = '0e8a16'; Description = 'Auto-release: tagged for next release' }
)

# Labels de GitHub defaults que NO se deben tocar
$GitHubDefaults = @('bug', 'documentation', 'duplicate', 'enhancement', 'good first issue', 'help wanted', 'invalid', 'question', 'wontfix')

# ============================================================
# Asignacion por repo
# Cada repo tiene: lista de labels Scheme B que debe tener
# ============================================================
$RepoLabels = @{
  'nova-java-13-bom'           = @('nova-platform', 'type:parent-pom', 'lifecycle:stable', 'framework:maven', 'area:bom', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-shared-02-pipelines'        = @('nova-platform', 'type:infra', 'lifecycle:stable', 'area:devops', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-shared-01-docs'          = @('nova-platform', 'type:docs', 'lifecycle:stable', 'area:documentation', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'dependencies')
  'nova-shared-03-infrastructure' = @('nova-platform', 'type:infra', 'lifecycle:beta', 'area:infrastructure', 'area:observability', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')

  'nova-java-01-api-standard'                    = @('nova-platform', 'type:library', 'lifecycle:stable', 'framework:java-pure', 'area:api-standard', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-10-api-standard-quarkus-extension'  = @('nova-platform', 'type:extension', 'lifecycle:beta', 'framework:quarkus', 'area:api-standard', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies', 'autorelease: pending', 'autorelease: tagged')
  'nova-java-08-commons-spring-boot-starter'     = @('nova-platform', 'type:starter', 'lifecycle:stable', 'framework:spring-boot', 'area:common', 'area:api-standard', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-02-date-utils'                      = @('nova-platform', 'type:library', 'lifecycle:stable', 'framework:java-pure', 'area:common', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-20-example'                         = @('nova-platform', 'type:instance', 'lifecycle:stable', 'framework:spring-boot', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-03-mapper-utils'                    = @('nova-platform', 'type:library', 'lifecycle:stable', 'framework:java-pure', 'area:common', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-04-mask-utils'                      = @('nova-platform', 'type:library', 'lifecycle:stable', 'framework:java-pure', 'area:common', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-notifications'                   = @('nova-platform', 'type:library', 'lifecycle:stable', 'framework:java-pure', 'framework:gradle', 'area:notifications', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies', 'autorelease: pending', 'autorelease: tagged')
  'nova-java-notifications-micronaut-module'  = @('nova-platform', 'type:module', 'lifecycle:beta', 'framework:micronaut', 'framework:gradle', 'area:notifications', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies', 'autorelease: pending', 'autorelease: tagged')
  'nova-java-notifications-quarkus-extension' = @('nova-platform', 'type:extension', 'lifecycle:beta', 'framework:quarkus', 'framework:gradle', 'area:notifications', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies', 'autorelease: pending', 'autorelease: tagged')
  'nova-java-notifications-spring-boot-starter' = @('nova-platform', 'type:starter', 'lifecycle:beta', 'framework:spring-boot', 'framework:gradle', 'area:notifications', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies', 'autorelease: pending', 'autorelease: tagged')
  'nova-java-09-observability-spring-boot-starter' = @('nova-platform', 'type:starter', 'lifecycle:stable', 'framework:spring-boot', 'area:observability', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-05-observability-utils'             = @('nova-platform', 'type:library', 'lifecycle:stable', 'framework:java-pure', 'area:observability', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-18-quarkus-archetype'               = @('nova-platform', 'type:archetype', 'lifecycle:stable', 'framework:quarkus', 'framework:maven', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-21-quarkus-example'                 = @('nova-platform', 'type:instance', 'lifecycle:stable', 'framework:quarkus', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-15-quarkus-parent'                  = @('nova-platform', 'type:parent-pom', 'lifecycle:stable', 'framework:quarkus', 'framework:maven', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-19-quarkus-template'                = @('nova-platform', 'type:template', 'lifecycle:stable', 'framework:quarkus', 'framework:gradle', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-17-spring-boot-archetype'           = @('nova-platform', 'type:archetype', 'lifecycle:stable', 'framework:spring-boot', 'framework:maven', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-16-spring-boot-gradle-plugin'       = @('nova-platform', 'type:plugin', 'lifecycle:stable', 'framework:spring-boot', 'framework:gradle', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-14-spring-boot-parent'              = @('nova-platform', 'type:parent-pom', 'lifecycle:stable', 'framework:spring-boot', 'framework:maven', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-java-12-spring-boot-starter'             = @('nova-platform', 'type:meta-starter', 'lifecycle:stable', 'framework:spring-boot', 'area:common', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-nestjs-commons'                       = @('nova-platform', 'type:library', 'lifecycle:beta', 'framework:nestjs', 'area:common', 'area:api-standard', 'area:observability', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-nestjs-observability-starter'         = @('nova-platform', 'type:starter', 'lifecycle:beta', 'framework:nestjs', 'area:observability', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-nestjs-parent'                        = @('nova-platform', 'type:docs', 'lifecycle:stable', 'framework:nestjs', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'nova-nestjs-starter'                       = @('nova-platform', 'type:meta-starter', 'lifecycle:beta', 'framework:nestjs', 'area:common', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')

  'demo-notifications-micronaut'    = @('nova-platform', 'type:demo', 'lifecycle:stable', 'framework:micronaut', 'framework:gradle', 'area:notifications', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'demo-notifications-quarkus'      = @('nova-platform', 'type:demo', 'lifecycle:stable', 'framework:quarkus', 'framework:gradle', 'area:notifications', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
  'demo-notifications-spring-boot'  = @('nova-platform', 'type:demo', 'lifecycle:stable', 'framework:spring-boot', 'framework:gradle', 'area:notifications', 'priority:critical', 'priority:high', 'priority:medium', 'priority:low', 'breaking-change', 'security', 'dependencies')
}

# ============================================================
# Helpers
# ============================================================
function Write-Banner { param([string]$Text) Write-Host ''; Write-Host ('=' * 70) -ForegroundColor Cyan; Write-Host ("  {0}" -f $Text) -ForegroundColor Cyan; Write-Host ('=' * 70) -ForegroundColor Cyan }
function Write-Info   { param([string]$Text) Write-Host "[i] $Text" -ForegroundColor Cyan }
function Write-Ok     { param([string]$Text) Write-Host "[+] $Text" -ForegroundColor Green }
function Write-Warn   { param([string]$Text) Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-Err    { param([string]$Text) Write-Host "[x] $Text" -ForegroundColor Red }

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

function Test-GhCli {
  gh --version 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "gh CLI no instalada." }
  gh auth status 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "gh CLI no autenticada." }
  Write-Info 'gh CLI OK'
}

function Get-SchemaBLabelDef {
  param([string]$Name)
  return $SchemeB | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
}

function Set-RepoLabel {
  param(
    [string]$Repo,
    [string]$LabelName
  )
  $target = "ahincho/$Repo"
  $def = Get-SchemaBLabelDef -Name $LabelName
  if (-not $def) {
    Write-Warn "Label '$LabelName' no esta en Scheme B, saltando."
    return
  }
  if ($DryRun) {
    Write-Host "  [DRY-RUN] gh label create $LabelName -R $target --color $($def.Color)" -ForegroundColor Yellow
    return
  }
  # gh label create is idempotent with --force (overwrites color)
  gh label create $LabelName -R $target --color $def.Color --description $def.Description --force 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Fall\u00f3 gh label create '$LabelName' en $target (exit $LASTEXITCODE)."
  }
}

function Remove-RepoLabel {
  param(
    [string]$Repo,
    [string]$LabelName
  )
  $target = "ahincho/$Repo"
  if ($DryRun) {
    Write-Host "  [DRY-RUN] gh label delete $LabelName -R $target" -ForegroundColor Yellow
    return
  }
  gh label delete $LabelName -R $target --yes 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Fall\u00f3 gh label delete '$LabelName' en $target (puede que no exista, OK)."
  }
}

function Get-ExistingLabels {
  param([string]$Repo)
  $target = "ahincho/$Repo"
  $labels = gh label list -R $target --json name 2>&1 | ConvertFrom-Json
  return @($labels | ForEach-Object { $_.name })
}

# ============================================================
# Main
# ============================================================
try {
  Test-GhCli

  Write-Banner 'Apply Scheme B labels to 32 Nova Platform + demo repos'
  $repos = @($RepoLabels.Keys | Sort-Object)
  Write-Info "Repos a procesar: $($repos.Count)"

  # Compute summary
  $totalCreate = ($RepoLabels.Values | ForEach-Object { $_.Count }) | Measure-Object -Sum
  Write-Info "Total labels a crear: $($totalCreate.Sum)"

  # Compute deletes upfront
  $toDelete = @{}
  foreach ($repo in $repos) {
    $existing = Get-ExistingLabels -Repo $repo
    $expected = $RepoLabels[$repo]
    $del = @()
    foreach ($l in $existing) {
      if ($expected -contains $l) { continue }
      if ($GitHubDefaults -contains $l) { continue }
      $del += $l
    }
    if ($del.Count -gt 0) {
      $toDelete[$repo] = $del
    }
  }
  $totalDel = ($toDelete.Values | ForEach-Object { $_.Count }) | Measure-Object -Sum
  Write-Info "Total labels a borrar (Scheme A): $($totalDel.Sum)"

  Confirm-Continue "Aplicar $($totalCreate.Sum) creates + $($totalDel.Sum) deletes en $($repos.Count) repos?"

  $createCount = 0
  $deleteCount = 0
  foreach ($repo in $repos) {
    Write-Host ''
    Write-Host "[i] Procesando $repo ..." -ForegroundColor Cyan

    # 1. Crear labels Scheme B esperados (idempotente con --force)
    foreach ($label in $RepoLabels[$repo]) {
      Set-RepoLabel -Repo $repo -LabelName $label
      $createCount++
    }

    # 2. Borrar labels que NO son Scheme B ni defaults
    if ($toDelete.ContainsKey($repo)) {
      foreach ($label in $toDelete[$repo]) {
        Remove-RepoLabel -Repo $repo -LabelName $label
        $deleteCount++
      }
    }
  }

  Write-Host ''
  Write-Ok "Completado: $createCount labels creados, $deleteCount labels borrados en $($repos.Count) repos."
  Write-Ok 'Script finalizado sin errores.'
}
catch {
  Write-Err $_.Exception.Message
  exit 1
}