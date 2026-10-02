BeforeAll {
  $script:wfPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-main-guard.yml'
  $script:wfContent = if (Test-Path -LiteralPath $script:wfPath) {
    Get-Content -LiteralPath $script:wfPath -Raw
  } else { '' }
}

Describe 'reusable-main-guard.yml - workflow structure' {
  It 'workflow file exists' {
    Test-Path -LiteralPath $script:wfPath | Should -BeTrue
  }

  It 'declares workflow_call trigger' {
    $script:wfContent | Should -Match 'workflow_call:'
  }

  It 'has the 3 expected inputs' {
    foreach ($inp in @('retries', 'retry-delay-seconds', 'message')) {
      $script:wfContent | Should -Match "(?m)^\s{6}${inp}:\s*$" -Because "input $inp must be declared"
    }
  }

  It 'retries defaults to 3 and the delay to 10 seconds' {
    $script:wfContent | Should -Match "(?ms)retries:.*?default:\s*3"
    $script:wfContent | Should -Match "(?ms)retry-delay-seconds:.*?default:\s*10"
  }
}

Describe 'reusable-main-guard.yml - permissions' {
  It 'declares contents: write to comment on the commit' {
    $script:wfContent | Should -Match 'contents:\s*write'
  }

  It 'declares pull-requests: read to find the pull request' {
    $script:wfContent | Should -Match 'pull-requests:\s*read'
  }
}

Describe 'reusable-main-guard.yml - behaviour' {
  It 'only accepts pull requests that were merged' {
    $script:wfContent | Should -Match 'select\(\.merged_at != null\)'
  }

  It 'comments on the commit and fails when there is no pull request' {
    $script:wfContent | Should -Match 'commits/\$SHA/comments'
    $script:wfContent | Should -Match '(?m)^\s+exit 1\s*$'
  }

  It 'passes inputs and context through env, never into the script' {
    $runBlock = [regex]::Match($script:wfContent, '(?ms)run:\s*\|\s*\n(.*)').Groups[1].Value
    $runBlock | Should -Not -Match '\$\{\{'
  }
}
