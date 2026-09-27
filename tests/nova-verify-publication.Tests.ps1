BeforeAll {
  $script:actionDir = Join-Path $PSScriptRoot '..\.github\actions\nova-verify-publication'
  $script:actionPath = Join-Path $script:actionDir 'action.yml'
  $script:actionText = if (Test-Path -LiteralPath $script:actionPath) {
    Get-Content -LiteralPath $script:actionPath -Raw
  } else { '' }

  # Returns the body of every run: key, both block scalars (run: |) and
  # single-line commands. A block ends at the first non-empty line indented at
  # or above the run: key.
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

  # @() keeps it an array: PowerShell unrolls a one-element return value, and
  # [0] would then index the first character of the only block.
  $script:runBlocks = @(Get-RunBlocks $script:actionText)

  # The input's block runs until the next input (2-space indent) or the next
  # top-level key, so a missing field cannot borrow a later one.
  function Get-InputBlock([string] $name) {
    return [regex]::Match($script:actionText, '(?ms)^  ' + [regex]::Escape($name) + ':\s*$(.*?)(?=^  \S|^\S)').Groups[1].Value
  }
}

Describe 'nova-verify-publication/action.yml - composite integrity' {
  It 'action.yml and README.md exist' {
    Test-Path -LiteralPath $script:actionPath | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $script:actionDir 'README.md') | Should -BeTrue
  }

  It 'declares composite runs type' {
    $script:actionText | Should -Match "using:\s*'composite'"
  }

  It 'requires group-id, artifact-ids, version and token' {
    foreach ($inp in @('group-id', 'artifact-ids', 'version', 'token')) {
      $block = Get-InputBlock $inp
      $block | Should -Not -BeNullOrEmpty -Because "input '$inp' must be declared"
      $block | Should -Match '(?m)^\s+required:\s*true\s*$' -Because "input '$inp' must be required"
    }
  }

  It 'declares the optional inputs with their defaults' {
    $expected = [ordered]@{
      'extensions'      = "'pom jar'"
      'repository'      = '${{ github.repository }}'
      'timeout-seconds' = "'300'"
    }
    foreach ($inp in $expected.Keys) {
      $block = Get-InputBlock $inp
      $block | Should -Not -BeNullOrEmpty -Because "input '$inp' must be declared"
      $block | Should -Match ('(?m)^\s+default:\s*' + [regex]::Escape($expected[$inp]) + '\s*$') -Because "input '$inp' must default to $($expected[$inp])"
    }
  }

  It 'calls no other action' {
    $script:actionText | Should -Not -Match '(?m)^\s*(?:-\s*)?uses:'
  }
}

Describe 'nova-verify-publication/action.yml - env-var wiring (Lote R)' {
  It 'has exactly one run block' {
    $script:runBlocks.Count | Should -Be 1
  }

  It 'never interpolates an expression inside the run block' {
    $script:runBlocks[0] | Should -Not -Match '\$\{\{'
  }

  It 'passes every input through env' {
    $wiring = [ordered]@{
      'GROUP_ID'        = 'group-id'
      'ARTIFACT_IDS'    = 'artifact-ids'
      'VERSION'         = 'version'
      'EXTENSIONS'      = 'extensions'
      'REPOSITORY'      = 'repository'
      'TOKEN'           = 'token'
      'TIMEOUT_SECONDS' = 'timeout-seconds'
    }
    foreach ($var in $wiring.Keys) {
      $script:actionText | Should -Match ('(?m)^\s+' + $var + ':\s+\$\{\{ inputs\.' + [regex]::Escape($wiring[$var]) + ' \}\}\s*$')
    }
  }
}

Describe 'nova-verify-publication/action.yml - behaviour' {
  It 'strips a leading v from the version' {
    $script:runBlocks[0] | Should -Match '\$\{VERSION#v\}'
  }

  It 'validates every input before building a URL' {
    foreach ($var in @('GROUP_ID', 'version', 'REPOSITORY', 'TIMEOUT_SECONDS', 'artifact', 'ext')) {
      $script:runBlocks[0] | Should -Match ('\[\[ "\$\{' + $var + '\}" =~') -Because "$var must be validated"
    }
  }

  It 'fails the job when a file cannot be downloaded' {
    $script:runBlocks[0] | Should -Match '::error::'
    $script:runBlocks[0] | Should -Match '(?m)^\s*exit 1\s*$'
  }

  It 'never prints the token' {
    foreach ($line in ($script:runBlocks[0] -split "`n")) {
      if ($line -match '\becho\b') {
        $line | Should -Not -Match 'TOKEN' -Because 'the token must not reach the log'
      }
    }
  }
}
