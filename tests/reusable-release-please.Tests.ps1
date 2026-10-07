BeforeAll {
  $script:wfPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-release-please.yml'
  $script:wfContent = if (Test-Path -LiteralPath $script:wfPath) {
    Get-Content -LiteralPath $script:wfPath -Raw
  } else { '' }
  # name in the workflow -> output of googleapis/release-please-action
  $script:outputs = [ordered]@{
    'release-created'  = 'release_created'
    'releases-created' = 'releases_created'
    'paths-released'   = 'paths_released'
    'tag-name'         = 'tag_name'
    'version'          = 'version'
    'sha'              = 'sha'
    'pr-created'       = 'prs_created'
  }
}

Describe 'reusable-release-please.yml - workflow structure' {
  It 'workflow file exists' {
    Test-Path -LiteralPath $script:wfPath | Should -BeTrue
  }

  It 'declares workflow_call trigger' {
    $script:wfContent | Should -Match 'workflow_call:'
  }

  It 'has the 4 expected inputs' {
    foreach ($inp in @('path', 'config-file', 'manifest-file', 'target-branch')) {
      $script:wfContent | Should -Match "(?m)^\s{6}${inp}:\s*$" -Because "input $inp must be declared"
    }
  }
}

Describe 'reusable-release-please.yml - outputs' {
  It 'the release-please step has the id the outputs read from' {
    $script:wfContent | Should -Match '(?ms)name: Run release-please\s*\n\s+id: release\s*\n\s+uses: googleapis/release-please-action@'
  }

  It 'exposes every output at workflow level from the job' {
    foreach ($name in $script:outputs.Keys) {
      $script:wfContent | Should -Match "(?ms)^\s{6}${name}:\s*\n.*?value: \`$\{\{ jobs\.release-please\.outputs\.${name} \}\}" -Because "workflow output $name must read the job output"
    }
  }

  It 'maps every job output to the matching output of the action' {
    foreach ($name in $script:outputs.Keys) {
      $actionKey = $script:outputs[$name]
      $script:wfContent | Should -Match "(?m)^\s{6}${name}: \`$\{\{ steps\.release\.outputs\.${actionKey} \}\}\s*$" -Because "job output $name must come from $actionKey"
    }
  }
}
