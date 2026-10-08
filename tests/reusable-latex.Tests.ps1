BeforeAll {
  $script:lintPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-latex-lint.yml'
  $script:buildPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-latex-build.yml'
  $script:lint = if (Test-Path -LiteralPath $script:lintPath) { Get-Content -LiteralPath $script:lintPath -Raw } else { '' }
  $script:build = if (Test-Path -LiteralPath $script:buildPath) { Get-Content -LiteralPath $script:buildPath -Raw } else { '' }

  # Same extraction as reusable-build-python.Tests.ps1: block scalars and
  # single-line run: commands alike. Only real steps count: a `run:` under
  # `with:` (texlive-action's input) is indented deeper than a step key.
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

  function Get-InputBlock([string] $text, [string] $name) {
    [regex]::Match($text, '(?ms)^      ' + [regex]::Escape($name) + ':\s*$(.*?)(?=^      \S|^\S|^  \S)').Groups[1].Value
  }

  $script:files = @{ 'reusable-latex-lint.yml' = $script:lint; 'reusable-latex-build.yml' = $script:build }
}

Describe 'reusable-latex-* - shared hardening' {
  It 'both workflow files exist' {
    Test-Path -LiteralPath $script:lintPath | Should -BeTrue
    Test-Path -LiteralPath $script:buildPath | Should -BeTrue
  }

  It 'are callable only as reusable workflows' {
    foreach ($name in $script:files.Keys) {
      $text = $script:files[$name]
      $text | Should -Match '(?m)^on:\s*\n\s{2}workflow_call:' -Because "$name is a reusable workflow"
      $text | Should -Not -Match '(?m)^  (push|pull_request|pull_request_target|schedule|workflow_dispatch|workflow_run|merge_group):' -Because "the caller of $name owns the triggers"
    }
  }

  It 'grant the token read-only contents and nothing else' {
    foreach ($name in $script:files.Keys) {
      $text = $script:files[$name]
      $text | Should -Match '(?m)^permissions:\s*\n\s{2}contents:\s*read\s*$' -Because "$name only reads"
      $text | Should -Not -Match '(?m)^\s+\w[\w-]*:\s*write\s*$' -Because "$name needs no write scope"
    }
  }

  It 'declare no workflow-level concurrency (a caller group or a matrix would cancel runs)' {
    foreach ($name in $script:files.Keys) {
      $script:files[$name] | Should -Not -Match '(?m)^concurrency:' -Because "$name is called once per matrix entry"
    }
  }

  It 'bound the job with timeout-minutes' {
    foreach ($name in $script:files.Keys) {
      $script:files[$name] | Should -Match '(?m)^\s{4}timeout-minutes:\s*\d+\s*$' -Because "$name must not hang for six hours"
    }
  }

  It 'check out without persisting the token in .git/config' {
    foreach ($name in $script:files.Keys) {
      $script:files[$name] | Should -Match '(?ms)uses:\s*actions/checkout@\S+.*?with:\s*\n\s+persist-credentials:\s*false' -Because "$name never pushes"
    }
  }

  It 'pin every uses: ref to a 40-char commit SHA with its version in a comment (Lote Q)' {
    foreach ($name in $script:files.Keys) {
      $refs = [regex]::Matches($script:files[$name], '(?m)^\s*(?:-\s*)?uses:\s*(\S+)(.*)$')
      $refs.Count | Should -BeGreaterOrEqual 1
      foreach ($m in $refs) {
        $m.Groups[1].Value | Should -Match '@[0-9a-f]{40}$' -Because "'$($m.Groups[1].Value)' in $name must be pinned to a commit SHA"
        $m.Groups[2].Value | Should -Match '#\s*v\d+' -Because "'$($m.Groups[1].Value)' in $name must name its version"
      }
    }
  }

  It 'never interpolate inputs or step outputs into a run: step (Lote R)' {
    foreach ($name in $script:files.Keys) {
      foreach ($block in (Get-RunBlocks $script:files[$name])) {
        $block | Should -Not -Match '\$\{\{\s*(inputs|steps)\.' -Because "$name must pass values through env"
      }
    }
  }
}

Describe 'reusable-latex-lint.yml - chktex' {
  It 'declares the three inputs with their types and defaults' {
    $expected = [ordered]@{
      'paths'            = @('string', "'*.tex'")
      'config-file'      = @('string', "'.chktexrc'")
      'fail-on-warnings' = @('boolean', 'true')
    }
    foreach ($inp in $expected.Keys) {
      $type, $default = $expected[$inp]
      $block = Get-InputBlock $script:lint $inp
      $block | Should -Not -BeNullOrEmpty -Because "input '$inp' must be declared"
      $block | Should -Match ('(?m)^\s+type:\s*' + $type + '\s*$')
      $block | Should -Match ('(?m)^\s+default:\s*' + [regex]::Escape($default) + '\s*$')
      $block | Should -Match '(?m)^\s+required:\s*false\s*$'
    }
  }

  It 'installs chktex from apt instead of pulling a TeX Live image' {
    $script:lint | Should -Match 'apt-get install -y -qq --no-install-recommends chktex'
    $script:lint | Should -Not -Match 'texlive-action'
  }

  It 'lints only tracked files and fails when none match' {
    $script:lint | Should -Match 'git ls-files --'
    $script:lint | Should -Match '::error::No tracked file matches'
  }

  It 'loads the caller config only when it exists' {
    $script:lint | Should -Match '(?ms)if \[ -f "\$CONFIG_FILE" \]; then\s*\n\s*args\+=\(-l "\$CONFIG_FILE"\)'
  }

  It 'lints each file on its own without following \input, with stdin closed' {
    $script:lint | Should -Match 'args=\(-q -v0 -I0\)'
    $script:lint | Should -Match 'chktex "\$\{args\[@\]\}" -f "\$format" "\$file" < /dev/null'
  }

  It 'turns every warning into a GitHub annotation on its line' {
    $script:lint | Should -Match ([regex]::Escape("format=`$'::warning file=%f,line=%l,col=%c,title=chktex %n::%m\n'"))
  }

  It 'fails on warnings only when fail-on-warnings is true' {
    $script:lint | Should -Match 'FAIL_ON_WARNINGS: \$\{\{ inputs\.fail-on-warnings \}\}'
    $script:lint | Should -Match "if \[ `"\`$count`" -gt 0 \] && \[ `"\`$FAIL_ON_WARNINGS`" = 'true' \]; then"
  }
}

Describe 'reusable-latex-build.yml - TeX Live build' {
  It 'declares the five inputs with their types and defaults' {
    $expected = [ordered]@{
      'command'        = @('string', "'./scripts/build.sh'")
      'scheme'         = @('string', "'full'")
      'artifact-name'  = @('string', "''")
      'artifact-path'  = @('string', "'build/*.pdf'")
      'retention-days' = @('number', '30')
    }
    foreach ($inp in $expected.Keys) {
      $type, $default = $expected[$inp]
      $block = Get-InputBlock $script:build $inp
      $block | Should -Not -BeNullOrEmpty -Because "input '$inp' must be declared"
      $block | Should -Match ('(?m)^\s+type:\s*' + $type + '\s*$')
      $block | Should -Match ('(?m)^\s+default:\s*' + [regex]::Escape($default) + '\s*$')
      $block | Should -Match '(?m)^\s+required:\s*false\s*$'
    }
  }

  It 'runs the caller command and scheme inside texlive-action' {
    $script:build | Should -Match '(?ms)uses:\s*xu-cheng/texlive-action@[0-9a-f]{40}.*?with:\s*\n\s+scheme: \$\{\{ inputs\.scheme \}\}\s*\n\s+run: \$\{\{ inputs\.command \}\}'
  }

  It 'uploads the artifact only when it has a name, and fails when no file matches' {
    $script:build | Should -Match "(?ms)if: inputs\.artifact-name != ''\s*\n\s+uses:\s*actions/upload-artifact@"
    $script:build | Should -Match 'if-no-files-found: error'
  }
}
