BeforeAll {
  $script:wfPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-supabase-migrations.yml'
  $script:wfText = if (Test-Path -LiteralPath $script:wfPath) {
    Get-Content -LiteralPath $script:wfPath -Raw
  } else { '' }

  # Same extraction as reusable-latex.Tests.ps1: block scalars and
  # single-line run: commands alike. Only real steps count: a `run:` indented
  # deeper than a step key would belong to a `with:` block.
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

  # Body of a key two levels under `inputs:` or `secrets:` (6 spaces).
  function Get-InputBlock([string] $text, [string] $name) {
    [regex]::Match($text, '(?ms)^      ' + [regex]::Escape($name) + ':\s*$(.*?)(?=^      \S|^\S|^  \S)').Groups[1].Value
  }

  # The steps of the job, in order, one string each and without comment lines,
  # so a comment that quotes a command is never taken for the command.
  function Get-Steps([string] $text) {
    $code = (($text -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    $m = [regex]::Match($code, '(?ms)^    steps:\s*\n(.*)\z')
    if (-not $m.Success) { return @() }
    return @([regex]::Split($m.Groups[1].Value, '(?m)^(?=      - )') | Where-Object { $_ -match '^      - ' })
  }

  function Find-Step([string] $pattern) {
    for ($i = 0; $i -lt $script:steps.Count; $i++) {
      if ($script:steps[$i] -match $pattern) { return $i }
    }
    return -1
  }

  $script:steps = Get-Steps $script:wfText
  $script:runBlocks = Get-RunBlocks $script:wfText
}

Describe 'reusable-supabase-migrations.yml - trigger and input surface' {
  It 'workflow file exists' {
    Test-Path -LiteralPath $script:wfPath | Should -BeTrue
  }

  It 'has the name and the description block of the other reusable workflows' {
    $script:wfText | Should -Match '(?m)^name: Reusable Supabase Migrations\s*$'
    $script:wfText | Should -Match '(?m)^description: \|\s*$'
  }

  It 'is callable only as a reusable workflow' {
    $script:wfText | Should -Match '(?m)^on:\s*\n\s{2}workflow_call:'
    $script:wfText | Should -Not -Match '(?m)^  (push|pull_request|pull_request_target|schedule|workflow_dispatch|workflow_run|merge_group):' -Because 'the caller owns the triggers'
  }

  It 'declares the four inputs with their types, requirement and defaults' {
    # name -> type, required, default (none for the required label)
    $expected = [ordered]@{
      'target'               = @('string', 'true',  $null)
      'supabase-cli-version' = @('string', 'false', "'2.116.0'")
      'working-directory'    = @('string', 'false', "'.'")
      'required-ref'         = @('string', 'false', "'refs/heads/main'")
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
        $block | Should -Not -Match '(?m)^\s+default:' -Because "input '$inp' has no sensible default"
      }
    }
  }

  It 'declares no other input' {
    $section = [regex]::Match($script:wfText, '(?ms)^    inputs:\s*\n(.*?)^    secrets:').Groups[1].Value
    $names = @([regex]::Matches($section, '(?m)^      ([\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
    (($names | Sort-Object) -join ',') | Should -Be 'required-ref,supabase-cli-version,target,working-directory'
  }

  It 'declares db-url as its only secret, and it is required' {
    $section = [regex]::Match($script:wfText, '(?ms)^    secrets:\s*\n(.*?)(?=^\S)').Groups[1].Value
    $names = @([regex]::Matches($section, '(?m)^      ([\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
    ($names -join ',') | Should -Be 'db-url'
    (Get-InputBlock $script:wfText 'db-url') | Should -Match '(?m)^\s+required:\s*true\s*$'
  }

  It 'documents the Session pooler and the percent-encoded password on the secret' {
    $block = Get-InputBlock $script:wfText 'db-url'
    $block | Should -Match 'Session pooler'
    $block | Should -Match 'IPv6-only' -Because 'that is why the direct connection does not work from a GitHub-hosted runner'
    $block | Should -Match 'percent-encoded'
  }
}

Describe 'reusable-supabase-migrations.yml - job hardening' {
  It 'grants the token read-only contents and nothing else' {
    $script:wfText | Should -Match '(?m)^permissions:\s*\n\s{2}contents:\s*read\s*$'
    $script:wfText | Should -Not -Match '(?m)^\s+\w[\w-]*:\s*write\s*$'
  }

  It 'declares no workflow-level concurrency: the group lives on the job' {
    $script:wfText | Should -Not -Match '(?m)^concurrency:'
  }

  It 'serializes the runs of one repository and target and never cancels one' {
    $block = [regex]::Match($script:wfText, '(?ms)^    concurrency:\s*\n(.*?)(?=^    \S|^\S|^  \S)').Groups[1].Value
    $block | Should -Match '(?m)^\s+group:\s*supabase-migrations-\$\{\{ github\.repository \}\}-\$\{\{ inputs\.target \}\}\s*$'
    $block | Should -Match '(?m)^\s+cancel-in-progress:\s*false\s*$' -Because 'a migration cut halfway leaves the database between two versions'
  }

  It 'names its own workflow in the group and never builds it from github.workflow' {
    $group = [regex]::Match($script:wfText, '(?m)^\s+group:\s*(\S.*?)\s*$').Groups[1].Value
    $group | Should -Not -BeNullOrEmpty
    $group | Should -Match 'supabase-migrations' -Because 'like the other reusables, so no two of them share a group'
    $group | Should -Not -Match 'github\.workflow' -Because "inside a called workflow it is the caller's name, which could collide with the caller's group"
  }

  It 'bounds the job with timeout-minutes' {
    $script:wfText | Should -Match '(?m)^\s{4}timeout-minutes:\s*\d+\s*$'
  }

  It 'names the job after the target' {
    $script:wfText | Should -Match '(?m)^\s{4}name:\s*Apply Supabase migrations \(\$\{\{ inputs\.target \}\}\)\s*$'
  }

  It 'hands the target to the scripts through a job-level env' {
    $script:wfText | Should -Match '(?m)^    env:\s*\n\s{6}TARGET:\s*\$\{\{ inputs\.target \}\}\s*$'
  }

  It 'runs its scripts with bash and no job-wide working-directory' {
    $defaults = [regex]::Match($script:wfText, '(?ms)^    defaults:\s*\n(.*?)(?=^    \S|^\S|^  \S)').Groups[1].Value
    $defaults | Should -Match '(?m)^\s+shell:\s*bash\s*$'
    $defaults | Should -Not -Match 'working-directory' -Because 'the ref check runs before the checkout, when that folder does not exist yet'
  }

  It 'checks out without persisting the token in .git/config' {
    $script:wfText | Should -Match '(?ms)uses:\s*actions/checkout@\S+[^\n]*\n\s+with:\s*\n(?:\s+[\w-]+:[^\n]*\n)*?\s+persist-credentials:\s*false'
  }
}

Describe 'reusable-supabase-migrations.yml - SHA pinning (Lote Q)' {
  It 'pins every uses: ref to a 40-char commit SHA with its version in a comment' {
    $refs = [regex]::Matches($script:wfText, '(?m)^\s*(?:-\s*)?uses:\s*(\S+)(.*)$')
    $refs.Count | Should -BeGreaterOrEqual 2
    foreach ($m in $refs) {
      $m.Groups[1].Value | Should -Match '@[0-9a-f]{40}$' -Because "'$($m.Groups[1].Value)' must be pinned to a commit SHA"
      $m.Groups[2].Value | Should -Match '#\s*v\d+\.\d+\.\d+' -Because "'$($m.Groups[1].Value)' must name its version"
    }
  }

  It 'runs no third-party code besides actions/checkout and supabase/setup-cli' {
    $actions = @([regex]::Matches($script:wfText, '(?m)^\s*(?:-\s*)?uses:\s*([^@\s]+)@') | ForEach-Object { $_.Groups[1].Value })
    (($actions | Sort-Object) -join ',') | Should -Be 'actions/checkout,supabase/setup-cli' -Because 'every action in the job can read the database credentials it is given'
  }
}

Describe 'reusable-supabase-migrations.yml - ref guard' {
  It 'is the first step, so a run from the wrong ref fails before anything is checked out or installed' {
    $script:steps.Count | Should -BeGreaterThan 0
    $script:steps[0] | Should -Not -Match '(?m)^\s+uses:'
    $script:steps[0] | Should -Match 'REQUIRED_REF'
    (Find-Step 'actions/checkout@') | Should -BeGreaterThan 0
  }

  It 'reads the ref of the run and the required ref through env' {
    $script:steps[0] | Should -Match '(?m)^\s+CURRENT_REF:\s*\$\{\{ github\.ref \}\}\s*$'
    $script:steps[0] | Should -Match '(?m)^\s+REQUIRED_REF:\s*\$\{\{ inputs\.required-ref \}\}\s*$'
  }

  It 'compares the two refs, and an empty required-ref skips the comparison' {
    $script:steps[0] | Should -Match ([regex]::Escape('if [ -n "$REQUIRED_REF" ] && [ "$CURRENT_REF" != "$REQUIRED_REF" ]; then'))
  }

  It 'fails with an ::error:: when the run comes from another ref' {
    $script:steps[0] | Should -Match '::error::'
    $script:steps[0] | Should -Match '(?m)^\s+exit 1\s*$'
  }
}

Describe 'reusable-supabase-migrations.yml - database URL' {
  It 'fails with an ::error:: when the secret is empty, before the checkout' {
    $check = Find-Step '-z "\$DB_URL"'
    $check | Should -BeGreaterOrEqual 0
    $check | Should -BeLessThan (Find-Step 'actions/checkout@')
    $script:steps[$check] | Should -Match '::error::The db-url secret'
    $script:steps[$check] | Should -Match '(?m)^\s+exit 1\s*$'
  }

  It 'hands the secret to each step that runs a script on it through env' {
    $withUrl = @($script:steps | Where-Object { $_ -match '\$DB_URL' })
    $withUrl.Count | Should -Be 4 -Because 'the emptiness check and the three supabase commands'
    foreach ($step in $withUrl) {
      $step | Should -Match '(?m)^\s+DB_URL:\s*\$\{\{ secrets\.db-url \}\}\s*$'
    }
  }

  It 'mentions the secret only as a step-level DB_URL env entry, never for the whole job' {
    $code = (($script:wfText -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' })
    $lines = @($code | Where-Object { $_ -match 'secrets\.' })
    $lines.Count | Should -BeGreaterOrEqual 1
    foreach ($line in $lines) {
      $line | Should -Match '^ {10}DB_URL:\s*\$\{\{ secrets\.db-url \}\}\s*$' -Because 'a secret reaches only the step that needs it, through env, so no other step or action can read it'
    }
  }

  It 'only tests the URL for emptiness or passes it as the --db-url argument, never prints it' {
    foreach ($block in $script:runBlocks) {
      $rest = $block -replace [regex]::Escape('[ -z "$DB_URL" ]'), '' -replace [regex]::Escape('--db-url "$DB_URL"'), ''
      $rest | Should -Not -Match 'DB_URL' -Because 'the connection string carries the password'
    }
  }
}

Describe 'reusable-supabase-migrations.yml - pipeline steps' {
  It 'runs the ref check, the secret check, the checkout, the CLI setup, the dry run, the push and the migration list, in that order' {
    $patterns = [ordered]@{
      'ref check'      = 'CURRENT_REF'
      'secret check'   = '-z "\$DB_URL"'
      'checkout'       = 'uses:\s*actions/checkout@'
      'CLI setup'      = 'uses:\s*supabase/setup-cli@'
      'dry run'        = 'supabase db push --db-url "\$DB_URL" --dry-run'
      'push'           = 'supabase db push --db-url "\$DB_URL" --yes'
      'migration list' = 'supabase migration list --db-url "\$DB_URL"'
    }
    $previous = -1
    foreach ($name in $patterns.Keys) {
      $index = Find-Step $patterns[$name]
      $index | Should -BeGreaterThan $previous -Because "the $name step must exist and come after the one before it"
      $previous = $index
    }
  }

  It 'sets up the CLI with the version of the input' {
    $setup = $script:steps[(Find-Step 'uses:\s*supabase/setup-cli@')]
    $setup | Should -Match '(?m)^\s+version:\s*\$\{\{ inputs\.supabase-cli-version \}\}\s*$'
  }

  It 'shows what is pending with a dry run, which needs no confirmation' {
    $dry = $script:steps[(Find-Step 'supabase db push --db-url "\$DB_URL" --dry-run')]
    $dry | Should -Not -Match '--yes'
  }

  It 'applies the migrations with --yes, because a CI run cannot answer the prompt' {
    $push = $script:steps[(Find-Step 'supabase db push --db-url "\$DB_URL" --yes')]
    $push | Should -Not -Match '--dry-run'
  }

  It 'runs three supabase commands and nothing else of the CLI' {
    $commands = @($script:runBlocks | ForEach-Object { $_ -split "`n" } | Where-Object { $_ -match '^\s*supabase\s' })
    $commands.Count | Should -Be 3
  }

  It 'runs the supabase steps in the working-directory input and no other step' {
    foreach ($step in $script:steps) {
      if ($step -match '(?m)^\s*supabase\s') {
        $step | Should -Match '(?m)^        working-directory:\s*\$\{\{ inputs\.working-directory \}\}\s*$' -Because 'the CLI looks for supabase/ in its working directory'
      } else {
        $step | Should -Not -Match 'working-directory' -Because 'the folder does not exist before the checkout, and these steps do not need it'
      }
    }
  }

  It 'fails before the dry run when the migrations folder is missing, because the CLI would exit 0 without applying anything' {
    $dry = $script:steps[(Find-Step 'supabase db push --db-url "\$DB_URL" --dry-run')]
    $dry | Should -Match '(?m)^\s+if \[ ! -d supabase/migrations \]; then\s*$'
    $dry | Should -Match '::error::No supabase/migrations folder'
    $dry.IndexOf('supabase/migrations') | Should -BeLessThan $dry.IndexOf('supabase db push')
  }

  It 'never interpolates a ${{ }} expression inside a run block' {
    $script:runBlocks.Count | Should -BeGreaterOrEqual 5
    foreach ($block in $script:runBlocks) {
      $block | Should -Not -Match '\$\{\{' -Because 'inputs, secrets and context values must reach the script through env'
    }
  }
}
