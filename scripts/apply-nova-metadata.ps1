#Requires -Version 5.1
<#
.SYNOPSIS
  Aplica metadata (descripciones y topics) a los 32 repos Nova Platform + demos
  en la cuenta personal ahincho.

.DESCRIPTION
  Estandariza:
    - Descriptions en ingles (migracion del espanol donde aplique).
    - Topics para los 5 repos que no los tenian.

  Esquema de labels (Esquema B) se aplica via apply-nova-labels.ps1 (separado).

  Idempotente: aplicar 2 veces da el mismo resultado.

.PARAMETER Phase
  descriptions : aplica solo descripciones (32 repos).
  topics       : aplica solo topics a los 5 repos faltantes.
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
  'nova-java-13-bom'              = 'Root Bill of Materials (BOM) for the Nova Platform meta-framework. Centralizes dependency versions for Java, NestJS and future stacks.'
  'nova-shared-02-pipelines'           = 'Reusable GitHub Actions workflows for CI/CD of the Nova Platform meta-framework (build, quality, publish for Maven and Gradle).'
  'nova-shared-01-docs'             = 'Nova Platform meta-framework documentation: ADRs (shared, java, nest), technical guides (semantic versioning, maturity evaluation, archetype comparison) and operational automation scripts.'
  'nova-shared-03-infrastructure'   = 'Infrastructure as code (Docker Compose) for the Nova Platform observability stack: OpenTelemetry Collector, Tempo, Loki, Mimir, Pyroscope and Grafana.'
  'nova-java-01-api-standard'                                   = 'Pure-Java library of API standards: ApiResponse/ApiError, HATEOAS links, PageInfo, FilterCriteria, RateLimitInfo, HttpStatusCode and UserAgentParser. Framework-agnostic.'
  'nova-java-10-api-standard-quarkus-extension'                 = 'Quarkus extension that integrates nova-api-standard: ApiExceptionMapper + ApiObjectMapperCustomizer auto-wired.'
  'nova-java-08-commons-spring-boot-starter'                    = 'Spring Boot starter that re-exports Nova pure libraries (api-standard, mask-utils) as auto-configured dependencies for Spring Boot applications.'
  'nova-java-02-date-utils'                                     = 'Pure-Java date utilities library: formatting, parsing, relative date calculation and timezone helpers. No Spring dependency.'
  'nova-example-01-spring-boot-reference'                                        = 'Nova Java meta-framework instance/demo. Shows real usage of Nova pure libraries and starters.'
  'nova-java-03-mapper-utils'                                   = 'Pure-Java object mapping library (MapStruct-like) and conversion helpers. No Spring dependency.'
  'nova-java-04-mask-utils'                                     = 'Pure-Java library for sensitive data masking (credit cards, emails, phones). No Spring dependency.'
  'nova-java-notifications'                                  = 'Nova Notifications core library: pure-Java (no framework), framework-agnostic facade for Email/SMS/Push/Slack with Resilience4j-style retry+circuit-breaker+rate-limit. Published to GitHub Packages.'
  'nova-java-notifications-micronaut-module'                 = 'Micronaut 5 module for Nova Notifications. @Factory + @ConfigurationProperties under nova.notifications.* prefix; supports Micronaut AOT and Shadow JAR.'
  'nova-java-notifications-quarkus-extension'                = 'Quarkus 3.33 LTS extension for Nova Notifications. CDI @Singleton + SmallRye Config @ConfigMapping under nova.notifications.* prefix; ships META-INF/jandex.idx so Quarkus build-time scan discovers beans.'
  'nova-java-notifications-spring-boot-starter'              = 'Spring Boot 4.1 auto-configuration starter for Nova Notifications. Wires NotificationFacade, RestClient-based REST exposure, and @ConfigurationProperties under nova.notifications.* prefix.'
  'nova-java-09-observability-spring-boot-starter'              = 'Spring Boot observability starter: Four Golden Signals (latency, traffic, errors, saturation), distributed tracing with OpenTelemetry and Spring Boot Actuator auto-configuration.'
  'nova-java-05-observability-utils'                            = 'Pure-Java observability utilities library: metrics, traces and logs without Spring coupling. OpenTelemetry SDK helpers.'
  'nova-java-18-quarkus-archetype'                              = 'Nova Platform Quarkus Maven archetype. Generates a multi-module (boot/product/shared) microservice skeleton on Java 25 + Quarkus 3.33.2.1 LTS.'
  'nova-example-04-quarkus-reference'                                = 'Quarkus instance of the Nova Platform meta-framework. Consumes nova-api-standard + nova-api-standard-quarkus-extension (twin of ahincho/nova-example-01-spring-boot-reference, which is Spring Boot).'
  'nova-java-15-quarkus-parent'                                 = 'Parent POM for Nova Platform Quarkus microservice instances. Centralizes Java 25 + Quarkus 3.33.2.1 LTS + plugins + nova-notifications-quarkus-extension dependency.'
  'nova-java-19-quarkus-template'                               = 'Gradle template for microservice instances built on the Nova Platform meta-framework with Quarkus 3.33.x LTS. Multi-module (shared + product + boot), Java 25, wired with nova-notifications-quarkus-extension.'
  'nova-java-17-spring-boot-archetype'                          = 'Maven archetype for generating a new Spring Boot project with Nova Platform meta-framework conventions and dependencies.'
  'nova-java-16-spring-boot-gradle-plugin'                      = 'Nova Platform Gradle plugin for Spring Boot projects: applies build conventions, configures Java toolchain and Spring Boot plugin automatically.'
  'nova-java-14-spring-boot-parent'                             = 'Parent POM for Spring Boot projects in the Nova Platform meta-framework: managed dependencies, plugins and centralized properties.'
  'nova-java-12-spring-boot-starter'                            = 'Nova Platform Spring Boot meta-starter: bundles all Nova starters (commons, observability) and configures the application to use the meta-framework.'
  'nova-nestjs-commons'                                      = 'Turborepo monorepo of common NestJS packages: nestjs-mask, nestjs-api-standard and nestjs-observability.'
  'nova-nestjs-observability-starter'                        = 'Dynamic NestJS observability module with OpenTelemetry: Four Golden Signals, distributed tracing, log correlation and OTLP exporters.'
  'nova-nestjs-parent'                                       = 'Shared configuration (TypeScript, ESLint, Prettier, Jest, TypeDoc) for NestJS projects in the Nova Platform meta-framework.'
  'nova-nestjs-starter'                                      = 'NestJS meta-framework: bootstrap factory that re-exports pure libraries and NestJS modules from the Nova Platform ecosystem.'
  'demo-notifications-micronaut'                             = 'Nova Notifications + Micronaut 5 demo. Controller-based example + @MicronautTest integration test that overrides the starter''s NotificationConfiguration bean.'
  'demo-notifications-quarkus'                               = 'Nova Notifications + Quarkus 3.33 LTS demo. JAX-RS resource example with notification.sendWelcomeEmail() and JUnit5 integration test for the Quarkus extension.'
  'demo-notifications-spring-boot'                           = 'Nova Notifications + Spring Boot 4.1 demo. End-to-end REST example with RestClient-based service + integration test that wires the Spring Boot starter.'
}

# ============================================================
# Data: Topics (5 repos that are missing them)
# ============================================================
$Topics = @{
  'nova-java-10-api-standard-quarkus-extension' = @('java', 'quarkus', 'quarkus-extension', 'nova-platform', 'library', 'framework-integration')
  'nova-java-18-quarkus-archetype'              = @('java', 'maven', 'archetype', 'quarkus', 'nova-platform', 'microservice-template')
  'nova-example-04-quarkus-reference'                = @('java', 'quarkus', 'nova-platform', 'demo', 'example', 'microservice-instance')
  'nova-java-15-quarkus-parent'                 = @('java', 'maven', 'parent-pom', 'quarkus', 'nova-platform', 'microservice-parent')
  'nova-java-19-quarkus-template'               = @('java', 'gradle', 'template', 'quarkus', 'nova-platform', 'microservice-template')
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
  Write-Banner 'Phase 2: apply topics (5 repos sin topics)'
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