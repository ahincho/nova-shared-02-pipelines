BeforeAll {
  $script:wfPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-merged-pr-gate.yml'
  $script:wfText = if (Test-Path -LiteralPath $script:wfPath) {
    Get-Content -LiteralPath $script:wfPath -Raw
  } else { '' }

  # Same extraction as reusable-supabase-migrations.Tests.ps1: block scalars
  # and single-line run: commands alike, step keys only (8 spaces).
  function Get-RunBlocks([string] $text) {
    $blocks = @()
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^(\s{8})run:\s*(.*)$') {
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

  # Body of a key two levels under `inputs:` (6 spaces).
  function Get-InputBlock([string] $text, [string] $name) {
    [regex]::Match($text, '(?ms)^      ' + [regex]::Escape($name) + ':\s*$(.*?)(?=^      \S|^    \S|^\S|^  \S)').Groups[1].Value
  }

  # Literal text as a regex, so scripts can be matched without escaping by hand.
  function Esc([string] $text) { [regex]::Escape($text) }

  $script:runBlocks = Get-RunBlocks $script:wfText
  $script:script = ($script:runBlocks -join "`n")
}

Describe 'reusable-merged-pr-gate.yml - trigger and interface' {
  It 'workflow file exists' {
    Test-Path -LiteralPath $script:wfPath | Should -BeTrue
  }

  It 'has the name and the description block of the other reusable workflows' {
    $script:wfText | Should -Match '(?m)^name: Reusable Merged PR Gate\s*$'
    $script:wfText | Should -Match '(?m)^description: \|\s*$'
  }

  It 'is callable only as a reusable workflow' {
    $script:wfText | Should -Match '(?m)^on:\s*\n\s{2}workflow_call:'
    $script:wfText | Should -Not -Match '(?m)^  (push|pull_request|pull_request_target|schedule|workflow_dispatch|workflow_run|merge_group):' -Because 'the caller owns the triggers'
  }

  It 'declares the three inputs with their types, requirement and defaults' {
    $expected = [ordered]@{
      'target'      = @('string', 'true',  $null)
      'base-branch' = @('string', 'false', "'main'")
      'ci-workflow' = @('string', 'false', "'ci.yml'")
    }
    foreach ($inp in $expected.Keys) {
      $type, $required, $default = $expected[$inp]
      $block = Get-InputBlock $script:wfText $inp
      $block | Should -Not -BeNullOrEmpty -Because "input '$inp' must be declared"
      $block | Should -Match ('(?m)^\s+type:\s*' + $type + '\s*$') -Because "input '$inp' must be a $type"
      $block | Should -Match ('(?m)^\s+required:\s*' + $required + '\s*$') -Because "input '$inp' must have required: $required"
      if ($default) {
        $block | Should -Match ('(?m)^\s+default:\s*' + [regex]::Escape($default) + '\s*$') -Because "input '$inp' must default to $default"
      } else {
        $block | Should -Not -Match '(?m)^\s+default:' -Because "input '$inp' must always be given"
      }
    }
  }

  It 'declares no other input' {
    $section = [regex]::Match($script:wfText, '(?ms)^    inputs:\s*\n(.*?)^    outputs:').Groups[1].Value
    $names = @([regex]::Matches($section, '(?m)^      ([\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
    (($names | Sort-Object) -join ',') | Should -Be 'base-branch,ci-workflow,target'
  }

  It 'declares no secret: it reads with the token of the run' {
    $script:wfText | Should -Not -Match '(?m)^    secrets:'
    $script:wfText | Should -Not -Match 'secrets\.'
  }

  It 'declares the outputs sha and pr-number, each read from the job' {
    $blocks = @([regex]::Matches($script:wfText, '(?ms)^    outputs:\s*\n(.*?)(?=^    \S|^\S)'))
    $blocks.Count | Should -Be 2 -Because 'one block under workflow_call and one on the job'
    $workflowLevel = $blocks[0].Groups[1].Value
    $names = @([regex]::Matches($workflowLevel, '(?m)^      ([\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
    (($names | Sort-Object) -join ',') | Should -Be 'pr-number,sha'
    foreach ($name in @('sha', 'pr-number')) {
      $workflowLevel | Should -Match ('(?ms)^      ' + $name + ':\s*\n.*?value: \$\{\{ jobs\.gate\.outputs\.' + $name + ' \}\}') -Because "workflow output $name must read the job output"
      $blocks[1].Groups[1].Value | Should -Match ('(?m)^      ' + $name + ': \$\{\{ steps\.resolve\.outputs\.' + $name + ' \}\}\s*$') -Because "job output $name must come from the resolve step"
    }
  }

  It 'writes both outputs from the step the job reads them from' {
    $script:wfText | Should -Match '(?ms)id: resolve\s*\n\s+env:'
    $script:script | Should -Match (Esc 'echo "sha=$sha" >> "$GITHUB_OUTPUT"')
    $script:script | Should -Match (Esc 'echo "pr-number=$number" >> "$GITHUB_OUTPUT"')
  }
}

Describe 'reusable-merged-pr-gate.yml - permissions and hardening' {
  It 'grants the token read access to actions, contents and pull requests and nothing else' {
    $block = [regex]::Match($script:wfText, '(?ms)^permissions:\s*\n(.*?)(?=^\S)').Groups[1].Value
    $pairs = @([regex]::Matches($block, '(?m)^  ([\w-]+):\s*(\S+)\s*$') | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value })
    (($pairs | Sort-Object) -join ',') | Should -Be 'actions=read,contents=read,pull-requests=read'
  }

  It 'tells the caller to grant those permissions' {
    $script:wfText | Should -Match '(?m)^# IMPORTANT: the CALLER workflow must declare these three scopes'
  }

  It 'declares no concurrency: the caller owns it' {
    $script:wfText | Should -Not -Match '(?m)^\s*concurrency:'
  }

  It 'bounds the job with timeout-minutes' {
    $script:wfText | Should -Match '(?m)^\s{4}timeout-minutes:\s*\d+\s*$'
  }

  It 'runs its script with bash, which it needs for [[ ]] and here-strings' {
    $script:wfText | Should -Match '(?ms)^    defaults:\s*\n\s+run:\s*\n\s+shell:\s*bash\s*$'
  }

  It 'runs no third-party action: gh and jq come with the runner' {
    $script:wfText | Should -Not -Match '(?m)^\s*(?:-\s*)?uses:'
  }

  It 'reads with the token of the run, through env' {
    $script:wfText | Should -Match '(?m)^\s+GH_TOKEN:\s*\$\{\{ github\.token \}\}\s*$'
  }

  It 'hands the three inputs to the script through env' {
    $script:wfText | Should -Match '(?m)^\s+TARGET:\s*\$\{\{ inputs\.target \}\}\s*$'
    $script:wfText | Should -Match '(?m)^\s+BASE:\s*\$\{\{ inputs\.base-branch \}\}\s*$'
    $script:wfText | Should -Match '(?m)^\s+CI_WORKFLOW:\s*\$\{\{ inputs\.ci-workflow \}\}\s*$'
  }

  It 'never interpolates a ${{ }} expression inside a run block' {
    $script:runBlocks.Count | Should -BeGreaterOrEqual 1
    foreach ($block in $script:runBlocks) {
      $block | Should -Not -Match '\$\{\{' -Because 'what a person types must reach the script through env'
    }
  }

  It 'never puts a value into the program of jq or gh api, only passes it with --arg' {
    $script:script | Should -Match (Esc 'jq -c --arg sha "$sha" --arg base "$BASE"')
    $script:script | Should -Match (Esc '.merge_commit_sha == $sha and .base.ref == $base')
    $script:script | Should -Not -Match '\\"\$' -Because 'a quote escaped around a shell variable is a value interpolated into a jq program'
  }
}

Describe 'reusable-merged-pr-gate.yml - resolution of the commit' {
  It 'fails through one function that prints an ::error:: and stops' {
    $script:script | Should -Match (Esc 'fail() { echo "::error::$1 Not deploying."; exit 1; }')
  }

  It 'accepts #224 and 224 by dropping hashes and whitespace first' {
    $script:script | Should -Match (Esc "target=`$(tr -d '#[:space:]' <<<`"`$TARGET`")")
  }

  It 'reads an all-digit value as a pull request number and checks it was merged into the base branch' {
    $script:script | Should -Match (Esc 'if [[ $target =~ ^[0-9]+$ ]]; then')
    $script:script | Should -Match (Esc 'pr=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$target") || fail "PR #$target does not exist."')
    $script:script | Should -Match (Esc '[ "$(jq -r .merged_at <<<"$pr")" != null ] || fail "PR #$target is not merged."')
    $script:script | Should -Match (Esc '[ "$(jq -r .base.ref <<<"$pr")" = "$BASE" ] || fail "PR #$target was not merged into $BASE."')
    $script:script | Should -Match (Esc 'sha=$(jq -r .merge_commit_sha <<<"$pr")')
  }

  It 'reads 7 to 40 hex characters as a commit and requires it to be the merge of a pull request into the base branch' {
    $script:script | Should -Match (Esc 'elif [[ $target =~ ^[0-9a-f]{7,40}$ ]]; then')
    $script:script | Should -Match (Esc 'sha=$(gh api "repos/$GITHUB_REPOSITORY/commits/$target" --jq .sha) || fail "Commit $target does not exist."')
    $script:script | Should -Match (Esc 'prs=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/pulls") || fail "Could not list the pull requests of $sha."')
    $script:script | Should -Match (Esc "[.[] | select(.merged_at != null and .merge_commit_sha == `$sha and .base.ref == `$base)][0] // empty")
    $script:script | Should -Match (Esc '[ -n "$pr" ] || fail "$sha is not the merge of a pull request into $BASE."')
  }

  It 'refuses anything that is neither of the two' {
    $script:script | Should -Match (Esc "fail `"'`$TARGET' is neither a PR number nor a SHA.`"")
  }

  It 'only goes on with a full 40-character SHA' {
    $script:script | Should -Match (Esc '[[ $sha =~ ^[0-9a-f]{40}$ ]] || fail')
  }

  It 'tries the pull request before the commit, so a value made only of digits is a pull request' {
    $script:script.IndexOf('=~ ^[0-9]+$', [StringComparison]::Ordinal) | Should -BeGreaterOrEqual 0
    $script:script.IndexOf('=~ ^[0-9]+$', [StringComparison]::Ordinal) | Should -BeLessThan $script:script.IndexOf('=~ ^[0-9a-f]{7,40}$', [StringComparison]::Ordinal)
  }

  It 'looks up the last pull_request run of the CI workflow on the head of the pull request, not on the merge commit' {
    $script:script | Should -Match (Esc 'head_sha=$(jq -r .head.sha <<<"$pr")')
    $script:script | Should -Match (Esc "ci=`$(gh run list --repo `"`$GITHUB_REPOSITORY`" --workflow `"`$CI_WORKFLOW`" --event pull_request --commit `"`$head_sha`" --limit 1 --json conclusion --jq '.[0].conclusion // empty')")
  }

  It 'requires that run to have concluded success, and says what it finished as' {
    $script:script | Should -Match (Esc '[ "$ci" = success ] || fail "CI of PR #$number on $head_sha finished as ''${ci:-no run}''."')
  }

  It 'writes the outputs only after every check has passed' {
    $outputs = $script:script.IndexOf('>> "$GITHUB_OUTPUT"', [StringComparison]::Ordinal)
    $outputs | Should -BeGreaterThan 0
    foreach ($check in @('is not merged', 'was not merged into', 'is not the merge of a pull request into', 'neither a PR number nor a SHA', '[ "$ci" = success ]')) {
      $at = $script:script.IndexOf($check, [StringComparison]::Ordinal)
      $at | Should -BeGreaterThan -1 -Because "the check '$check' must exist"
      $at | Should -BeLessThan $outputs -Because "the check '$check' must come before the outputs are written"
    }
  }

  It 'refuses with a message of its own when a gh call fails or no full SHA comes out' {
    $script:script | Should -Match (Esc "fail `"'`$TARGET' did not resolve to a full commit SHA.`"")
    $script:script | Should -Match (Esc 'fail "Could not list the runs of $CI_WORKFLOW."')
  }

  It 'words every refusal in English' {
    $messages = @([regex]::Matches($script:script, 'fail "([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
    $messages.Count | Should -Be 10 -Because 'one message per way of refusing'
    $script:script | Should -Not -Match '(?i)\b(no existe|fusionad|mergead|despliegu|desplieg)' -Because 'the messages are in English'
  }
}
