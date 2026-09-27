BeforeAll {
  $script:gradleWf = Join-Path $PSScriptRoot '..\.github\workflows\reusable-sonarcloud-gradle.yml'
  $script:mavenWf  = Join-Path $PSScriptRoot '..\.github\workflows\reusable-sonarcloud-maven.yml'
  $script:gradleContent = if (Test-Path -LiteralPath $script:gradleWf) {
    Get-Content -LiteralPath $script:gradleWf -Raw
  } else { '' }
  $script:mavenContent = if (Test-Path -LiteralPath $script:mavenWf) {
    Get-Content -LiteralPath $script:mavenWf -Raw
  } else { '' }
}

Describe 'reusable-sonarcloud-{gradle,maven}.yml - input surface (Lote R parametrization)' {
  It 'Gradle variant declares the expected 19 inputs' {
    $expected = @(
      'sonar-org', 'sonar-project-key',
      'java-version', 'gradle-version', 'jacoco-report-path',
      'sonar-host-url',
      'wait-for-quality-gate', 'quality-gate-timeout',
      'coverage-threshold', 'new-code-coverage-threshold',
      'sonar-sources', 'sonar-tests',
      'sonar-exclusions', 'sonar-test-exclusions', 'sonar-coverage-exclusions',
      'branch', 'pull-request-base',
      'fail-on-missing-token', 'dry-run'
    )
    foreach ($inp in $expected) {
      $pattern = "(?m)^\s{6}${inp}:\s*$"
      $script:gradleContent | Should -Match $pattern -Because "Gradle input '$inp' must be declared"
    }
  }

  It 'Maven variant declares the expected 18 inputs (no gradle-version)' {
    $expected = @(
      'sonar-org', 'sonar-project-key',
      'java-version', 'jacoco-report-path',
      'sonar-host-url',
      'wait-for-quality-gate', 'quality-gate-timeout',
      'coverage-threshold', 'new-code-coverage-threshold',
      'sonar-sources', 'sonar-tests',
      'sonar-exclusions', 'sonar-test-exclusions', 'sonar-coverage-exclusions',
      'branch', 'pull-request-base',
      'fail-on-missing-token', 'dry-run'
    )
    foreach ($inp in $expected) {
      $pattern = "(?m)^\s{6}${inp}:\s*$"
      $script:mavenContent | Should -Match $pattern -Because "Maven input '$inp' must be declared"
    }
  }

  It 'sonar-org and sonar-project-key are the only required inputs' {
    $script:gradleContent | Should -Match "(?ms)sonar-org:.*?required:\s*true"
    $script:gradleContent | Should -Match "(?ms)sonar-project-key:.*?required:\s*true"
    $script:mavenContent  | Should -Match "(?ms)sonar-org:.*?required:\s*true"
    $script:mavenContent  | Should -Match "(?ms)sonar-project-key:.*?required:\s*true"

    foreach ($inp in @('java-version', 'jacoco-report-path', 'sonar-host-url',
                       'wait-for-quality-gate', 'quality-gate-timeout',
                       'coverage-threshold', 'new-code-coverage-threshold',
                       'sonar-sources', 'sonar-tests',
                       'sonar-exclusions', 'sonar-test-exclusions', 'sonar-coverage-exclusions',
                       'branch', 'pull-request-base', 'fail-on-missing-token', 'dry-run')) {
      $script:gradleContent | Should -Match "(?ms)${inp}:.*?required:\s*false"
      $script:mavenContent  | Should -Match "(?ms)${inp}:.*?required:\s*false"
    }
  }
}

Describe 'reusable-sonarcloud-{gradle,maven}.yml - CodeQL-safe env var wiring (Lote Q hardening)' {
  # Lote Q: every input.X and steps.X.outputs.Y is routed through env vars to
  # avoid direct ${{}} interpolation in run: blocks (which triggers CodeQL
  # actions/code-injection medium alerts).

  It 'inputs.X are NEVER directly interpolated in run: blocks' {
    # Extract the run: block content (between run: > and the next top-level key)
    $gradleRun = ($script:gradleContent -split '(?ms)run:\s*>')[1]
    if ($gradleRun) { $gradleRun = ($gradleRun -split '(?ms)^    env:')[0] }
    $mavenRun  = ($script:mavenContent  -split '(?ms)run:\s*>')[1]
    if ($mavenRun)  { $mavenRun  = ($mavenRun  -split '(?ms)^    env:')[0] }
    $gradleRun | Should -Not -Match '\${{ inputs\.'
    $mavenRun  | Should -Not -Match '\${{ inputs\.'
    $gradleRun | Should -Not -Match '\${{ steps\.'
    $mavenRun  | Should -Not -Match '\${{ steps\.'
  }

  It 'Each input is captured as an env var before run:' {
    $captures = @(
        @{ pattern = 'SONAR_ORG:';                     key = 'sonar-org' }
        @{ pattern = 'SONAR_PROJECT_KEY:';             key = 'sonar-project-key' }
        @{ pattern = 'SONAR_HOST_URL:';                key = 'sonar-host-url' }
        @{ pattern = 'SONAR_SOURCES:';                 key = 'sonar-sources' }
        @{ pattern = 'SONAR_TESTS:';                   key = 'sonar-tests' }
        @{ pattern = 'SONAR_EXCLUSIONS:';              key = 'sonar-exclusions' }
        @{ pattern = 'SONAR_TEST_EXCLUSIONS:';         key = 'sonar-test-exclusions' }
        @{ pattern = 'SONAR_COVERAGE_EXCLUSIONS:';     key = 'sonar-coverage-exclusions' }
        @{ pattern = 'JACOCO_REPORT_PATH:';            key = 'jacoco-report-path' }
        @{ pattern = 'SONAR_COVERAGE_THRESHOLD:';      key = 'coverage-threshold' }
        @{ pattern = 'SONAR_NEW_CODE_COVERAGE_THRESHOLD:'; key = 'new-code-coverage-threshold' }
        @{ pattern = 'SONAR_WAIT_FOR_QG:';             key = 'wait-for-quality-gate' }
        @{ pattern = 'SONAR_QG_TIMEOUT:';              key = 'quality-gate-timeout' }
        @{ pattern = 'SONAR_DRY_RUN:';                 key = 'dry-run' }
    )
    foreach ($c in $captures) {
      $regex = '(?m)^\s+' + [regex]::Escape($c.pattern) + '\s+\${{ inputs\.' + [regex]::Escape($c.key) + ' }}'
      $script:gradleContent | Should -Match $regex -Because "gradle must capture $($c.key) as $($c.pattern)"
      $script:mavenContent  | Should -Match $regex -Because "maven must capture $($c.key) as $($c.pattern)"
    }
  }

  It 'steps.branch.outputs are wired via env vars' {
    $script:gradleContent | Should -Match '(?m)^\s+SONAR_BRANCH:\s+\${{ steps\.branch\.outputs\.branch }}'
    $script:gradleContent | Should -Match '(?m)^\s+SONAR_PR_BASE:\s+\${{ steps\.branch\.outputs\.pr_base }}'
    $script:mavenContent  | Should -Match '(?m)^\s+SONAR_BRANCH:\s+\${{ steps\.branch\.outputs\.branch }}'
    $script:mavenContent  | Should -Match '(?m)^\s+SONAR_PR_BASE:\s+\${{ steps\.branch\.outputs\.pr_base }}'
  }
}

Describe 'reusable-sonarcloud-{gradle,maven}.yml - run block uses env vars via double-quoted expansion' {
  # Each -Dsonar.X="\$SONAR_X" must appear in the run block. To avoid regex
  # special-char pain, use [regex]::Escape() on the literal target string.
  # Construct literals using [char]34 to avoid PowerShell quoting issues.

  $dbq = [char]34
  $checks = @(
    @{ prop = 'sonar.organization';                envVar = 'SONAR_ORG' }
    @{ prop = 'sonar.projectKey';                  envVar = 'SONAR_PROJECT_KEY' }
    @{ prop = 'sonar.host.url';                    envVar = 'SONAR_HOST_URL' }
    @{ prop = 'sonar.branch.name';                 envVar = 'SONAR_BRANCH' }
    @{ prop = 'sonar.pullrequest.base';            envVar = 'SONAR_PR_BASE' }
    @{ prop = 'sonar.sources';                     envVar = 'SONAR_SOURCES' }
    @{ prop = 'sonar.tests';                       envVar = 'SONAR_TESTS' }
    @{ prop = 'sonar.exclusions';                  envVar = 'SONAR_EXCLUSIONS' }
    @{ prop = 'sonar.test.exclusions';             envVar = 'SONAR_TEST_EXCLUSIONS' }
    @{ prop = 'sonar.coverage.exclusions';         envVar = 'SONAR_COVERAGE_EXCLUSIONS' }
    @{ prop = 'sonar.qualitygate.wait';            envVar = 'SONAR_WAIT_FOR_QG' }
    @{ prop = 'sonar.qualitygate.timeout';         envVar = 'SONAR_QG_TIMEOUT' }
    @{ prop = 'sonar.coverage.threshold';          envVar = 'SONAR_COVERAGE_THRESHOLD' }
    @{ prop = 'sonar.new-code.coverage.threshold'; envVar = 'SONAR_NEW_CODE_COVERAGE_THRESHOLD' }
    @{ prop = 'sonar.scanner.dumpToFile';          envVar = 'SONAR_DRY_RUN' }
  )
  foreach ($c in $checks) {
    $literal = '-' + $c.prop + '=' + $dbq + '$' + $c.envVar + $dbq
    $regex   = [regex]::Escape($literal)
    It "gradle uses -$($c.prop)=\`$$($c.envVar)" {
      $script:gradleContent | Should -Match $regex
    }
    It "maven uses -$($c.prop)=\`$$($c.envVar)" {
      $script:mavenContent  | Should -Match $regex
    }
  }
}

Describe 'reusable-sonarcloud-{gradle,maven}.yml - sonar-exclusions defaults' {
  It 'sonar-exclusions defaults exclude generated/, build/, *.class (Gradle)' {
    $script:gradleContent | Should -Match 'sonar-exclusions:'
    $script:gradleContent | Should -Match 'build/\*\*'
    $script:gradleContent | Should -Match 'generated/\*\*'
    $script:gradleContent | Should -Match '\*\.class'
  }

  It 'sonar-exclusions defaults exclude generated/, target/, *.class (Maven)' {
    $script:mavenContent | Should -Match 'sonar-exclusions:'
    $script:mavenContent | Should -Match 'target/\*\*'
    $script:mavenContent | Should -Match 'generated/\*\*'
    $script:mavenContent | Should -Match '\*\.class'
  }
}

Describe 'reusable-sonarcloud-{gradle,maven}.yml - Branch strategy' {
  It 'Both variants resolve branch via a dedicated step (id: branch)' {
    $script:gradleContent | Should -Match 'id: branch'
    $script:mavenContent  | Should -Match 'id: branch'
  }

  It 'Branch resolution prefers input.branch over GitHub auto-detect' {
    $script:gradleContent | Should -Match 'INPUT_BRANCH'
    $script:mavenContent  | Should -Match 'INPUT_BRANCH'
  }

  It 'PR analysis uses PR number as branch' {
    $script:gradleContent | Should -Match 'PR_NUMBER'
    $script:mavenContent  | Should -Match 'PR_NUMBER'
  }
}

Describe 'reusable-sonarcloud-{gradle,maven}.yml - Behavior flags' {
  It 'wait-for-quality-gate defaults to true (the hardening)' {
    $script:gradleContent | Should -Match "(?ms)wait-for-quality-gate:.*?default:\s*true"
    $script:mavenContent  | Should -Match "(?ms)wait-for-quality-gate:.*?default:\s*true"
  }

  It 'fail-on-missing-token defaults to false (skip-with-warning, dormant mode)' {
    $script:gradleContent | Should -Match "(?ms)fail-on-missing-token:.*?default:\s*false"
    $script:mavenContent  | Should -Match "(?ms)fail-on-missing-token:.*?default:\s*false"
  }

  It 'check-token step enforces fail-on-missing-token when true' {
    $script:gradleContent | Should -Match 'FAIL_ON_MISSING'
    $script:mavenContent  | Should -Match 'FAIL_ON_MISSING'
    $script:gradleContent | Should -Match 'fail-on-missing-token=true.*Failing'
    $script:mavenContent  | Should -Match 'fail-on-missing-token=true.*Failing'
  }

  It 'dry-run defaults to false' {
    $script:gradleContent | Should -Match "(?ms)dry-run:.*?default:\s*false"
    $script:mavenContent  | Should -Match "(?ms)dry-run:.*?default:\s*false"
  }
}

Describe 'reusable-sonarcloud-{gradle,maven}.yml - SHA-pinned (Lote Q compliance)' {
  It 'Both files have the Lote Q header comment (mentions SHA-pin)' {
    $script:gradleContent | Should -Match 'SHA.?pin'
    $script:mavenContent  | Should -Match 'SHA.?pin'
  }

  It 'Both files have SHA pins on all external uses: refs' {
    $script:gradleContent | Should -Match 'actions/checkout@[0-9a-f]{40}'
    $script:gradleContent | Should -Match 'actions/setup-java@[0-9a-f]{40}'
    $script:gradleContent | Should -Match 'gradle/actions/setup-gradle@[0-9a-f]{40}'
    $script:mavenContent  | Should -Match 'actions/checkout@[0-9a-f]{40}'
    $script:mavenContent  | Should -Match 'actions/setup-java@[0-9a-f]{40}'
  }

  It 'No file has @main branch pins on internal actions (Lote Q superseded Lote P)' {
    $script:gradleContent | Should -Not -Match 'ahincho/nova-shared-02-pipelines/\.github/actions/[a-z-]+@main\b'
    $script:mavenContent  | Should -Not -Match 'ahincho/nova-shared-02-pipelines/\.github/actions/[a-z-]+@main\b'
  }
}