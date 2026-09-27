BeforeAll {
  $script:actionPath = Join-Path $PSScriptRoot '..\.github\actions\nova-resolve-token\action.yml'
  $script:actionContent = $null
  $script:actionDoc = $null
  if (Test-Path -LiteralPath $script:actionPath) {
    $script:actionContent = Get-Content -LiteralPath $script:actionPath -Raw
    try {
      $script:actionDoc = (Get-Content -LiteralPath $script:actionPath -Raw) | python -c "import sys, yaml; print(yaml.safe_load(sys.stdin))" 2>&1
      # python prints dict repr; convert to hashtable-ish via ConvertFrom-Yaml if available, else parse
      # Fallback: use PowerShell's ConvertFrom-Yaml if Python returned a string
      if ($script:actionDoc -is [string]) {
        try {
          $script:actionDoc = $script:actionDoc | ConvertFrom-Json -ErrorAction Stop
        } catch {
          # Last resort: just keep as string
        }
      }
    } catch {
      $script:actionDoc = $null
    }
  }

  # Read as plain text for regex-based assertions
  $script:actionText = if ($script:actionContent) { $script:actionContent } else { '' }
}

Describe 'nova-resolve-token/action.yml - composite integrity' {
  It 'action.yml file exists' {
    Test-Path -LiteralPath $script:actionPath | Should -BeTrue
  }

  It 'declares composite runs type' {
    $script:actionText | Should -Match 'using:\s*''composite'''
  }

  It 'declares app-id input' {
    $script:actionText | Should -Match "(?m)^\s{2}app-id:\s*$"
  }

  It 'declares app-private-key input' {
    $script:actionText | Should -Match "(?m)^\s{2}app-private-key:\s*$"
  }

  It 'declares app-owner input with default ahincho' {
    $script:actionText | Should -Match "(?m)^\s{2}app-owner:\s*$"
    $script:actionText | Should -Match "(?m)default:\s*'ahincho'"
  }

  It 'declares value output' {
    $script:actionText | Should -Match "(?m)^\s{2}value:\s*$"
  }

  It 'declares source output' {
    $script:actionText | Should -Match "(?m)^\s{2}source:\s*$"
  }

  It 'has App token generation step' {
    $script:actionText | Should -Match 'actions/create-github-app-token@v2'
  }

  It 'App token step is conditional on non-empty inputs' {
    $script:actionText | Should -Match "if: inputs\.app-id != '' && inputs\.app-private-key != ''"
  }

  It 'has resolve step using bash' {
    $script:actionText | Should -Match "shell: bash"
  }

  It 'declares the three token inputs, github-token defaulting to github.token' {
    $script:actionText | Should -Match "(?m)^\s{2}packages-read-token:\s*$"
    $script:actionText | Should -Match "(?m)^\s{2}legacy-token:\s*$"
    $script:actionText | Should -Match "(?m)^\s{2}github-token:\s*$"
    $script:actionText | Should -Match '(?m)^\s+default:\s*\$\{\{ github\.token \}\}\s*$'
  }

  # A composite action has no secrets context: GitHub refuses to load one that
  # references it. That is what broke every caller from 2026-07-21 to 2026-09-27.
  It 'never references the secrets context' {
    $script:actionText | Should -Not -Match '\$\{\{\s*secrets\.'
  }

  It 'reads each token from its input' {
    $script:actionText | Should -Match 'TOKEN_PRIMARY:\s+\$\{\{ inputs\.packages-read-token \}\}'
    $script:actionText | Should -Match 'TOKEN_LEGACY:\s+\$\{\{ inputs\.legacy-token \}\}'
    $script:actionText | Should -Match 'TOKEN_GITHUB:\s+\$\{\{ inputs\.github-token \}\}'
  }
}

Describe 'nova-resolve-token/action.yml - priority order' {
  It 'checks APP_TOKEN first' {
    # The first `if [ -n "..." ]` block must reference APP_TOKEN
    $firstCheck = [regex]::Match($script:actionText, '(?s)if \[ -n "\$\{(\w+)').Groups[1].Value
    $firstCheck | Should -Be 'APP_TOKEN'
  }

  # GITHUB_TOKEN is always present, so it has to come last: ranked before the
  # PAT it won every time, and a cross-repo read could never succeed.
  It 'checks the App token, the PAT, the legacy PAT and GITHUB_TOKEN, in that order' {
    $order = [regex]::Matches($script:actionText, '(?m)^\s*(?:el)?if \[ -n "\$\{(\w+)\}" \]') | ForEach-Object { $_.Groups[1].Value }
    ($order -join ',') | Should -Be 'APP_TOKEN,TOKEN_PRIMARY,TOKEN_LEGACY,TOKEN_GITHUB'
  }

  It 'emits notice when PAT is used' {
    $script:actionText | Should -Match '::notice::NOVA_PACKAGES_READ_TOKEN'
  }

  It 'emits warning when legacy PAT is used' {
    $script:actionText | Should -Match '::warning::NOVA_RELEASE_PAT'
  }

  It 'emits warning when no token resolved' {
    $script:actionText | Should -Match '::warning::No read token resolved'
  }
}

Describe 'nova-resolve-token/action.yml - source labels are documented' {
  It 'source output documents all 5 possible values' {
    $script:actionText | Should -Match 'GITHUB_APP_TOKEN'
    $script:actionText | Should -Match 'GITHUB_TOKEN'
    $script:actionText | Should -Match 'NOVA_PACKAGES_READ_TOKEN'
    $script:actionText | Should -Match 'NOVA_RELEASE_PAT'
    $script:actionText | Should -Match 'NONE'
  }
}

Describe 'nova-resolve-token callers - App auth wired in 5 workflows' {
  BeforeAll {
    $script:workflowsDir = Join-Path $PSScriptRoot '..\.github\workflows'
    $script:expectedCallers = @(
      'reusable-build-maven.yml'
      'reusable-build-gradle.yml'
      'reusable-build-matrix.yml'
      'reusable-owasp-check.yml'
      'reusable-sbom.yml'
    )
  }

  It 'each expected caller wires NOVA_PLATFORM_APP_ID' {
    foreach ($f in $script:expectedCallers) {
      $path = Join-Path $script:workflowsDir $f
      $content = Get-Content -LiteralPath $path -Raw
      $content | Should -Match 'NOVA_PLATFORM_APP_ID' -Because "$f must wire the App ID secret"
    }
  }

  It 'each expected caller wires NOVA_PLATFORM_APP_PRIVATE_KEY' {
    foreach ($f in $script:expectedCallers) {
      $path = Join-Path $script:workflowsDir $f
      $content = Get-Content -LiteralPath $path -Raw
      $content | Should -Match 'NOVA_PLATFORM_APP_PRIVATE_KEY' -Because "$f must wire the App private key secret"
    }
  }

  It 'each expected caller passes both PATs as inputs' {
    foreach ($f in $script:expectedCallers) {
      $content = Get-Content -LiteralPath (Join-Path $script:workflowsDir $f) -Raw
      $content | Should -Match 'packages-read-token:\s+\$\{\{ secrets\.NOVA_PACKAGES_READ_TOKEN \}\}' -Because "$f must pass NOVA_PACKAGES_READ_TOKEN to the action"
      $content | Should -Match 'legacy-token:\s+\$\{\{ secrets\.NOVA_RELEASE_PAT \}\}' -Because "$f must pass NOVA_RELEASE_PAT to the action"
    }
  }

  It 'all callers pin the action to the same commit' {
    $pins = foreach ($f in $script:expectedCallers) {
      $content = Get-Content -LiteralPath (Join-Path $script:workflowsDir $f) -Raw
      $m = [regex]::Match($content, 'nova-resolve-token@([0-9a-f]{40})')
      $m.Success | Should -BeTrue -Because "$f must pin nova-resolve-token to a commit SHA"
      $m.Groups[1].Value
    }
    @($pins | Sort-Object -Unique).Count | Should -Be 1
  }
}