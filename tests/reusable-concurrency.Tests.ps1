BeforeAll {
  $script:workflowsDir = Join-Path $PSScriptRoot '..\.github\workflows'

  # Returns the concurrency group of a workflow file, or $null when it has no
  # workflow-level concurrency block.
  function Get-ConcurrencyGroup([string] $path) {
    $text = Get-Content -LiteralPath $path -Raw
    $m = [regex]::Match($text, '(?ms)^concurrency:\s*$.*?^\s+group:\s*(.+?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
  }

  $script:groups = @{}
  foreach ($file in Get-ChildItem -LiteralPath $script:workflowsDir -Filter 'reusable-*.yml') {
    $group = Get-ConcurrencyGroup $file.FullName
    if ($group) { $script:groups[$file.Name] = $group }
  }
}

# Inside a called workflow github.workflow is the caller's name. A group built
# only from it is the same for every reusable workflow a CI run calls, so each
# one cancelled the others: from 2026-07-21 to 2026-09-27 a pull request never
# got its matrix, OWASP, SBOM and Sonar jobs.
Describe 'reusable workflows - concurrency groups' {
  It 'the four build and check workflows still declare a group' {
    foreach ($f in @('reusable-build-gradle.yml', 'reusable-build-maven.yml', 'reusable-build-matrix.yml', 'reusable-owasp-check.yml')) {
      $script:groups.ContainsKey($f) | Should -BeTrue -Because "$f cancels its own superseded runs"
    }
  }

  It 'each group names its own workflow, so two reusables called by one run never share it' {
    foreach ($f in $script:groups.Keys) {
      $own = $f -replace '^reusable-', '' -replace '\.yml$', ''
      $script:groups[$f] | Should -Match ([regex]::Escape($own)) -Because "$f must not share a group with the other reusables"
    }
  }

  It 'no two reusables share a group' {
    $values = @($script:groups.Values)
    @($values | Sort-Object -Unique).Count | Should -Be $values.Count
  }
}
