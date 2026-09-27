BeforeAll {
  $script:wfPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-build-python.yml'
  $script:wfText = if (Test-Path -LiteralPath $script:wfPath) {
    Get-Content -LiteralPath $script:wfPath -Raw
  } else { '' }

  # Same extraction as nova-setup-python.Tests.ps1: block scalars and
  # single-line run: commands alike.
  function Get-RunBlocks([string] $text) {
    $blocks = @()
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^(\s*)run:\s*(.*)$') {
        $indent = $Matches[1].Length
        $rest = $Matches[2]
        if ($rest -match '^[|>][+-]?\s*$') {
          $body = @()
          for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ($line.Trim() -ne '' -and ($line.Length - $line.TrimStart().Length) -le $indent) { break }
            $body += $line
          }
          $blocks += ($body -join "`n")
        } else {
          $blocks += $rest
        }
      }
    }
    return $blocks
  }

  $script:runBlocks = Get-RunBlocks $script:wfText
}

Describe 'reusable-build-python.yml - trigger and input surface' {
  It 'workflow file exists' {
    Test-Path -LiteralPath $script:wfPath | Should -BeTrue
  }

  It 'is callable only as a reusable workflow' {
    $script:wfText | Should -Match '(?m)^on:\s*\n\s{2}workflow_call:'
    $script:wfText | Should -Not -Match '(?m)^  (push|pull_request|pull_request_target|schedule|workflow_dispatch|workflow_run|merge_group):' -Because 'the caller owns the triggers'
  }

  It 'declares the seven inputs with their types and defaults' {
    $expected = [ordered]@{
      'python-version'    = @('string', "''")
      'uv-version'        = @('string', "''")
      'working-directory' = @('string', "'.'")
      'cache'             = @('boolean', 'true')
      'lint'              = @('boolean', 'true')
      'format'            = @('boolean', 'true')
      'test'              = @('boolean', 'true')
    }
    foreach ($inp in $expected.Keys) {
      $type, $default = $expected[$inp]
      $block = [regex]::Match($script:wfText, '(?ms)^      ' + [regex]::Escape($inp) + ':\s*$(.*?)(?=^      \S|^\S|^  \S)').Groups[1].Value
      $block | Should -Not -BeNullOrEmpty -Because "input '$inp' must be declared"
      $block | Should -Match ('(?m)^\s+type:\s*' + $type + '\s*$') -Because "input '$inp' must be a $type"
      $block | Should -Match ('(?m)^\s+default:\s*' + [regex]::Escape($default) + '\s*$') -Because "input '$inp' must default to $default"
      $block | Should -Match '(?m)^\s+required:\s*false\s*$' -Because "input '$inp' must be optional"
    }
  }
}

Describe 'reusable-build-python.yml - job hardening' {
  It 'grants the token read-only contents and nothing else' {
    $script:wfText | Should -Match '(?m)^permissions:\s*\n\s{2}contents:\s*read\s*$'
    $script:wfText | Should -Not -Match '(?m)^\s+\w[\w-]*:\s*write\s*$'
  }

  It 'declares no workflow-level concurrency (it would deadlock with a caller group)' {
    $script:wfText | Should -Not -Match '(?m)^concurrency:'
  }

  It 'bounds the job with timeout-minutes' {
    $script:wfText | Should -Match '(?m)^\s{4}timeout-minutes:\s*\d+\s*$'
  }

  It 'checks out without persisting the token in .git/config' {
    $script:wfText | Should -Match '(?ms)uses:\s*actions/checkout@\S+.*?with:\s*\n\s+persist-credentials:\s*false'
  }
}

Describe 'reusable-build-python.yml - SHA pinning (Lote Q)' {
  It 'pins every uses: ref to a 40-char commit SHA' {
    $refs = [regex]::Matches($script:wfText, '(?m)^\s*(?:-\s*)?uses:\s*(\S+)')
    $refs.Count | Should -BeGreaterOrEqual 2
    foreach ($m in $refs) {
      $ref = $m.Groups[1].Value
      $ref | Should -Match '@[0-9a-f]{40}$' -Because "'$ref' must be pinned to a commit SHA"
    }
  }

  It 'pins external actions with their version in a comment' {
    $script:wfText | Should -Match 'uses:\s*actions/checkout@[0-9a-f]{40}\s+#\s*v\d+\.\d+\.\d+'
  }

  It 'uses nova-setup-python at the SHA the header comment declares' {
    $header = [regex]::Match($script:wfText, 'Internal actions \(ahincho/nova-shared-02-pipelines/\.github/actions/\*\): pinned to commit ([0-9a-f]{40})').Groups[1].Value
    $used = [regex]::Match($script:wfText, 'uses:\s*ahincho/nova-shared-02-pipelines/\.github/actions/nova-setup-python@([0-9a-f]{40})').Groups[1].Value
    $header | Should -Not -BeNullOrEmpty
    $used | Should -Be $header -Because 'a SHA bump must update the header and the uses: ref together'
  }
}

Describe 'reusable-build-python.yml - pipeline steps' {
  It 'passes the setup inputs through to nova-setup-python' {
    foreach ($inp in @('python-version', 'uv-version', 'working-directory', 'cache')) {
      $script:wfText | Should -Match ('(?m)^\s+' + [regex]::Escape($inp) + ':\s+\$\{\{ inputs\.' + [regex]::Escape($inp) + ' \}\}\s*$') -Because "'$inp' must reach the composite action"
    }
  }

  It 'runs lint, format check and tests, each behind its toggle' {
    $script:wfText | Should -Match '(?ms)if:\s*inputs\.lint\s*\n\s+run:\s*uv run --no-sync ruff check --output-format=github \.'
    $script:wfText | Should -Match '(?ms)if:\s*inputs\.format\s*\n\s+run:\s*uv run --no-sync ruff format --diff \.'
    $script:wfText | Should -Match '(?ms)if:\s*inputs\.test\s*\n\s+run:\s*uv run --no-sync pytest'
  }

  It 'never lets a tool re-resolve dependencies after the locked sync' {
    $uvRuns = @($script:runBlocks | Where-Object { $_ -match '\buv run\b' })
    $uvRuns.Count | Should -Be 3
    foreach ($block in $uvRuns) {
      $block | Should -Match 'uv run --no-sync' -Because 'the environment was already synced with --locked'
    }
  }

  It 'never interpolates ${{ inputs.X }} or ${{ steps.X }} inside a run block' {
    foreach ($block in $script:runBlocks) {
      $block | Should -Not -Match '\$\{\{\s*(inputs|steps)\.'
    }
  }
}
