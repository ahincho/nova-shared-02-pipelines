#Requires -Version 5.1
<#
.SYNOPSIS
  Aplica metadata (descripciones y topics) a los 32 repos de Nova Platform
  en la cuenta personal ahincho.

.DESCRIPTION
  Estandariza:
    - Descriptions en ingles (migracion del espanol donde aplique).
    - Topics para los 7 repos que no los tenian.

  Esquema de labels (Esquema B) se aplica via apply-nova-labels.ps1 (separado).

  Idempotente: aplicar 2 veces da el mismo resultado.

.PARAMETER Phase
  descriptions : aplica solo descripciones (32 repos).
  topics       : aplica solo topics a los 7 repos faltantes.
  all          : ejecuta las dos fases.

.PARAMETER DryRun
  Solo muestra las acciones que realizaria sin ejecutarlas.

.PARAMETER Force
  Omite la confirmacion interactiva antes de cada fase.

.EXAMPLE
  # Ver que haria sin aplicar
  powershell -ExecutionPolicy Bypass -File scripts/apply-nova-metadata.ps1 -Phase all -DryRun

.EXAMPLE
  # Aplicar todo (descripciones + topics)
  powershell -ExecutionPolicy Bypass -File scripts/apply-nova-metadata.ps1 -Phase all
#>

[CmdletBinding()]
param(
  [Parameter()]
  [ValidateSet('descriptions', 'topics', 'all')]
  [string]$Phase = 'all',

  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ============================================================
# Data: Descriptions (32 repos, English)
# ============================================================
$Descriptions = @{
  'nova-java-13-bom'              = 'Bill of Materials for the Nova Platform Java stack: nova-bom for the pure libraries, plus one BOM per framework (Spring Boot, Quarkus and Micronaut).'
  'nova-shared-02-pipelines'           = 'Reusable GitHub Actions workflows for CI/CD of the Nova Platform meta-framework (build, quality, publish for Maven and Gradle).'
  'nova-shared-01-docs'             = 'Nova Platform meta-framework documentation: ADRs (shared, java, nest), technical guides (semantic versioning, maturity evaluation, archetype comparison) and operational automation scripts.'
  'nova-shared-03-infrastructure'   = 'Infrastructure as code (Docker Compose) for the Nova Platform observability stack: OpenTelemetry Collector, Tempo, Loki, Mimir, Pyroscope and Grafana.'
  'nova-java-01-api-standard'                                   = 'Pure-Java library of API standards: ApiResponse/ApiError, HATEOAS links, PageInfo, FilterCriteria, RateLimitInfo, HttpStatusCode and UserAgentParser. Framework-agnostic.'
  'nova-java-10-api-standard-quarkus-extension'                 = 'Quarkus extension that integrates nova-api-standard: ApiExceptionMapper + ApiObjectMapperCustomizer auto-wired.'
  'nova-java-11-keycloak-quarkus-extension'                     = 'Quarkus extension for Nova Keycloak. CDI @Singleton + SmallRye Config @ConfigMapping under the nova.keycloak.* prefix; ships META-INF/jandex.idx so Quarkus build-time scan discovers beans.'
  'nova-java-08-commons-spring-boot-starter'                    = 'Spring Boot starter that re-exports Nova pure libraries (api-standard, mask-utils) as auto-configured dependencies for Spring Boot applications.'
  'nova-java-02-date-utils'                                     = 'Pure-Java date utilities library: formatting, parsing, relative date calculation and timezone helpers. No Spring dependency.'
  'nova-example-01-spring-boot-reference'                                        = 'Nova Java meta-framework instance/demo. Shows real usage of Nova pure libraries and starters.'
  'nova-example-02-spring-boot-ms-course'                                        = 'Spring Boot example on Nova Platform: a course service instrumented with @Traced and @Metered through the observability starter. Twin of nova-example-05-quarkus-ms-course.'
  'nova-example-03-spring-boot-ms-forum'                                         = 'Spring Boot example on Nova Platform: a second instrumented service with a deliberate error path, so the dashboards have two services and an error rate to show.'
  'nova-java-03-mapper-utils'                                   = 'Pure-Java object mapping library (MapStruct-like) and conversion helpers. No Spring dependency.'
  'nova-java-04-mask-utils'                                     = 'Pure-Java library for sensitive data masking (credit cards, emails, phones). No Spring dependency.'
  'nova-java-09-observability-spring-boot-starter'              = 'Spring Boot observability starter: Four Golden Signals (latency, traffic, errors, saturation), distributed tracing with OpenTelemetry and Spring Boot Actuator auto-configuration.'
  'nova-java-05-observability-utils'                            = 'Pure-Java observability utilities library: metrics, traces and logs without Spring coupling. OpenTelemetry SDK helpers.'
  'nova-java-06-keycloak'                                       = 'Nova Keycloak core library: pure-Java (no framework) token and user profile management for Keycloak-issued JWTs. Extracts public payload claims (sub, preferred_username, email, roles, realm_access) and exposes them through a framework-agnostic facade.'
  'nova-java-07-architecture-rules'                             = 'JUnit 5 + ArchUnit abstract tests enforcing Nova Platform architectural styles (Layered, Clean, Hexagonal).'
  'nova-java-18-quarkus-archetype'                              = 'Nova Platform Quarkus Maven archetype. Generates a multi-module (boot/product/shared) microservice skeleton on Java 25 + Quarkus 3.33.2.1 LTS.'
  'nova-example-04-quarkus-reference'                                = 'Quarkus instance of the Nova Platform meta-framework. Consumes nova-api-standard + nova-api-standard-quarkus-extension (twin of ahincho/nova-example-01-spring-boot-reference, which is Spring Boot).'
  'nova-example-05-quarkus-ms-course'                                = 'Example microservice instance consuming nova-java-quarkus-parent. Parallel to instances/ms-course (the Spring Boot instance).'
  'nova-example-06-quarkus-code-with-nova'                           = 'Minimal Quarkus example (a code.quarkus.io scaffold) with nova-api-standard-quarkus-extension: the ApiResponse envelope and exception mapping without writing a mapper.'
  'nova-java-15-quarkus-parent'                                 = 'Parent POM for Nova Platform Quarkus microservice instances. Centralizes Java 25 + Quarkus 3.33.2.1 LTS + plugins + nova-notifications-quarkus-extension dependency.'
  'nova-java-19-quarkus-template'                               = 'Gradle template for microservice instances built on the Nova Platform meta-framework with Quarkus 3.33.x LTS. Multi-module (shared + product + boot), Java 25, wired with nova-notifications-quarkus-extension.'
  'nova-java-17-spring-boot-archetype'                          = 'Maven archetype for generating a new Spring Boot project with Nova Platform meta-framework conventions and dependencies.'
  'nova-java-16-spring-boot-gradle-plugin'                      = 'Nova Platform Gradle plugin for Spring Boot projects: applies build conventions, configures Java toolchain and Spring Boot plugin automatically.'
  'nova-java-14-spring-boot-parent'                             = 'Parent POM for Spring Boot projects in the Nova Platform meta-framework: managed dependencies, plugins and centralized properties.'
  'nova-java-12-spring-boot-starter'                            = 'Nova Platform Spring Boot meta-starter: bundles all Nova starters (commons, observability) and configures the application to use the meta-framework.'
  'nova-nestjs-01-platform'                                     = 'Nova Platform meta-framework for NestJS: the ApiResponse envelope, framework wiring and the shared toolchain, published to GitHub Packages as @ahincho/nova-nestjs, @ahincho/nova-nestjs-toolchain and @ahincho/nova-nestjs-schematics.'
  'nova-nestjs-02-profile-utp'                                  = 'UTP''s organization profile for Nova Platform: the conventions its services share, declared once'
  'nova-example-07-nestjs-reference'                            = 'Reference NestJS service built on the Nova Platform meta-framework, consumed from GitHub Packages.'
  'nova-example-08-nestjs-generated'                            = 'Un servicio NestJS tal como lo emite el generador de Nova Platform, sin una sola linea escrita a mano. Instantanea de la 0.15.0, regenerada en cada release.'
}

# ============================================================
# Data: Topics (7 repos that are missing them)
# ============================================================
$Topics = @{
  'nova-java-10-api-standard-quarkus-extension' = @('java', 'quarkus', 'quarkus-extension', 'nova-platform', 'library', 'framework-integration')
  'nova-java-18-quarkus-archetype'              = @('java', 'maven', 'archetype', 'quarkus', 'nova-platform', 'microservice-template')
  'nova-example-04-quarkus-reference'                = @('java', 'quarkus', 'nova-platform', 'demo', 'example', 'microservice-instance')
  'nova-java-15-quarkus-parent'                 = @('java', 'maven', 'parent-pom', 'quarkus', 'nova-platform', 'microservice-parent')
  'nova-java-19-quarkus-template'               = @('java', 'gradle', 'template', 'quarkus', 'nova-platform', 'microservice-template')
  'nova-nestjs-02-profile-utp'                  = @('nestjs', 'nova-platform', 'typescript')
  'nova-example-08-nestjs-generated'            = @('example', 'nestjs', 'nova-platform')
}

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

function Write-Info { param([string]$Text) Write-Host "[i] $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "[+] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-Err  { param([string]$Text) Write-Host "[x] $Text" -ForegroundColor Red }

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
  $ver = gh --version 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "gh CLI no esta instalado o no esta en PATH."
  }
  $auth = gh auth status 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "gh CLI no esta autenticada. Ejecuta 'gh auth login' primero."
  }
  Write-Info 'gh CLI OK'
}

function Set-Description {
  param([string]$Repo, [string]$Description)
  $target = "ahincho/$Repo"
  if ($DryRun) {
    Write-Host "  [DRY-RUN] gh repo edit $target --description <$Description.Length chars>" -ForegroundColor Yellow
    return
  }
  gh repo edit $target --description $Description 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Fall\u00f3 gh repo edit para $target (exit $LASTEXITCODE)."
  }
}

function Set-Topics {
  param([string]$Repo, [string[]]$Topics)
  $target = "ahincho/$Repo"
  $topicList = $Topics -join ' '
  if ($DryRun) {
    Write-Host "  [DRY-RUN] gh repo edit $target --add-topic $($Topics -join ' --add-topic ')" -ForegroundColor Yellow
    return
  }
  # Clear existing topics first to avoid duplicates (gh --add-topic adds but does not replace).
  # Use --remove-topic for current ones, then --add-topic for new.
  $currentTopicsJson = gh api "repos/$target/topics" 2>&1 | ConvertFrom-Json
  if ($currentTopicsJson.names) {
    foreach ($t in $currentTopicsJson.names) {
      gh repo edit $target --remove-topic $t 2>&1 | Out-Null
    }
  }
  # Add new topics
  foreach ($t in $Topics) {
    gh repo edit $target --add-topic $t 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Fall\u00f3 gh repo edit --add-topic $t en $target (exit $LASTEXITCODE)."
    }
  }
}

# ============================================================
# Fases
# ============================================================
function Invoke-Descriptions {
  Write-Banner 'Phase 1: apply descriptions (32 repos)'
  $names = @($Descriptions.Keys | Sort-Object)
  Write-Info "Repos a actualizar: $($names.Count)"
  Confirm-Continue "Actualizar $($names.Count) descripciones?"

  $count = 0
  foreach ($repo in $names) {
    Set-Description -Repo $repo -Description $Descriptions[$repo]
    Write-Ok "$repo"
    $count++
  }
  Write-Ok "Fase descriptions completa: $count repos actualizados."
}

function Invoke-Topics {
  Write-Banner 'Phase 2: apply topics (7 repos sin topics)'
  $names = @($Topics.Keys | Sort-Object)
  Write-Info "Repos a actualizar: $($names.Count)"
  foreach ($repo in $names) {
    Write-Info "  - $repo : $($Topics[$repo] -join ', ')"
  }
  Confirm-Continue "Aplicar topics a $($names.Count) repos?"

  $count = 0
  foreach ($repo in $names) {
    Set-Topics -Repo $repo -Topics $Topics[$repo]
    Write-Ok "$repo"
    $count++
  }
  Write-Ok "Fase topics completa: $count repos actualizados."
}

# ============================================================
# Main
# ============================================================
try {
  Test-GhCli

  switch ($Phase) {
    'descriptions' { Invoke-Descriptions }
    'topics'       { Invoke-Topics }
    'all' {
      Invoke-Descriptions
      Invoke-Topics
    }
  }

  Write-Host ''
  Write-Ok 'Script finalizado sin errores.'
}
catch {
  Write-Err $_.Exception.Message
  exit 1
}