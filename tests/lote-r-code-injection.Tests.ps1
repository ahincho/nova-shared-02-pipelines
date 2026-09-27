BeforeAll {
  $script:loteRFiles = @(
    @{ name = 'reusable-sbom.yml';                  path = '..\.github\workflows\reusable-sbom.yml' }
    @{ name = 'reusable-owasp-check.yml';           path = '..\.github\workflows\reusable-owasp-check.yml' }
    @{ name = 'reusable-release-publish.yml';       path = '..\.github\workflows\reusable-release-publish.yml' }
    @{ name = 'reusable-build-matrix.yml';          path = '..\.github\workflows\reusable-build-matrix.yml' }
    @{ name = 'nova-publish-aggregator/action.yml'; path = '..\.github\actions\nova-publish-aggregator\action.yml' }
    @{ name = 'nova-gather-facts/action.yml';       path = '..\.github\actions\nova-gather-facts\action.yml' }
    @{ name = 'nova-setup-gpg/action.yml';          path = '..\.github\actions\nova-setup-gpg\action.yml' }
    @{ name = 'nova-validate-build/action.yml';     path = '..\.github\actions\nova-validate-build\action.yml' }
  )

  $script:contents = @{}
  foreach ($f in $script:loteRFiles) {
    $fullPath = Join-Path $PSScriptRoot $f.path
    if (Test-Path -LiteralPath $fullPath) {
      $script:contents[$f.name] = Get-Content -LiteralPath $fullPath -Raw
    } else {
      $script:contents[$f.name] = ''
    }
  }
}

# In PowerShell single-quoted strings:
#   \$  is literally \$  (in regex: matches a single $)
#   {{  is literally {{  (no special meaning in regex)
#   }}  is literally }}  (no special meaning in regex)
# So to match the literal ${{ in the file, write '\${{' in single-quoted PS.

Describe 'Lote R: env-var pattern (no ${{ inputs.X }} in run: blocks)' {

  It 'No file has unfixed ${{ inputs.X }} inside any run: block' {
    foreach ($f in $script:loteRFiles) {
      $content = $script:contents[$f.name]
      if ([string]::IsNullOrEmpty($content)) { continue }
      # Terminate at the next step-level key (indent <= 6) like 'env:', 'if:',
      # or the start of the next list item ('- name:') at indent 6.
      $matches = [regex]::Matches($content, '(?ms)run:\s*\|[+-]?\s*\n(.*?)(?=^\s{0,6}\w+:|^\s{4,6}- \w+:|\Z)')
      foreach ($m in $matches) {
        $block = $m.Groups[1].Value
        $hasInputsInject = $block -match '\${{ inputs\.'
        $hasInputsInject | Should -BeFalse -Because ('{0}: run block has ${{ inputs.X }}' -f $f.name)
      }
    }
  }

  It 'No file has unfixed ${{ steps.X.outputs.Y }} inside any run: block' {
    foreach ($f in $script:loteRFiles) {
      $content = $script:contents[$f.name]
      if ([string]::IsNullOrEmpty($content)) { continue }
      $matches = [regex]::Matches($content, '(?ms)run:\s*\|[+-]?\s*\n(.*?)(?=^\s{0,6}\w+:|^\s{4,6}- \w+:|\Z)')
      foreach ($m in $matches) {
        $block = $m.Groups[1].Value
        $hasStepsInject = $block -match '\${{ steps\.'
        $hasStepsInject | Should -BeFalse -Because ('{0}: run block has ${{ steps.X.outputs.Y }}' -f $f.name)
      }
    }
  }
}

Describe 'Lote Q: SHA-pinned (no @main or @vX on internal actions)' {

  It 'No file has @main branch pins on internal actions' {
    foreach ($f in $script:loteRFiles) {
      $content = $script:contents[$f.name]
      if ([string]::IsNullOrEmpty($content)) { continue }
      $hasMainPin = $content -match 'ahincho/nova-shared-02-pipelines/\.github/(workflows|actions)/[a-z0-9-]+@main\b'
      $hasMainPin | Should -BeFalse -Because "$($f.name): @main pin on internal ref"
    }
  }

  It 'No file has @vX.Y.Z tag pins on internal actions' {
    foreach ($f in $script:loteRFiles) {
      $content = $script:contents[$f.name]
      if ([string]::IsNullOrEmpty($content)) { continue }
      $hasVTag = $content -match 'ahincho/nova-shared-02-pipelines/\.github/(workflows|actions)/[a-z0-9-]+@v\d+'
      $hasVTag | Should -BeFalse -Because "$($f.name): @vX pin on internal ref"
    }
  }
}

Describe 'reusable-sbom.yml - env-var wiring (Lote R)' {
  It 'Captures inputs.sbom-format as SBOM_FORMAT env var' {
    $script:contents['reusable-sbom.yml'] | Should -Match 'SBOM_FORMAT:\s+\${{ inputs\.sbom-format'
  }
  It 'Captures inputs.build-tool as BUILD_TOOL env var' {
    $script:contents['reusable-sbom.yml'] | Should -Match 'BUILD_TOOL:\s+\${{ inputs\.build-tool'
  }
  It 'Uses ${SBOM_FORMAT} in run blocks' {
    $script:contents['reusable-sbom.yml'] | Should -Match '\$\{SBOM_FORMAT\}'
  }
  It 'Uses ${BUILD_TOOL} in run blocks' {
    $script:contents['reusable-sbom.yml'] | Should -Match '\$\{BUILD_TOOL\}'
  }
}

Describe 'reusable-owasp-check.yml - env-var wiring (Lote R)' {
  It 'Captures inputs.fail-on-cvss as FAIL_ON_CVSS env var' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match 'FAIL_ON_CVSS:\s+\${{ inputs\.fail-on-cvss'
  }
  It 'Captures inputs.suppression-file as SUPPRESSION_FILE' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match 'SUPPRESSION_FILE:\s+\${{ inputs\.suppression-file'
  }
  It 'Captures inputs.analyzer-override as ANALYZER_OVERRIDE (with vars fallback)' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match 'ANALYZER_OVERRIDE:\s+\${{ inputs\.analyzer-override \|\| vars\.DEPENDENCY_CHECK_ANALYZERS'
  }
  It 'Captures steps.cve-suppressions.outputs.suppressions-file as DYN_SUPPRESSIONS_FILE' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match 'DYN_SUPPRESSIONS_FILE:\s+\${{ steps\.cve-suppressions\.outputs\.suppressions-file'
  }
  It 'Uses ${FAIL_ON_CVSS} in the Maven run block' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match '\$\{FAIL_ON_CVSS\}'
  }
  It 'Uses ${SUPPRESSION_FILE} in the Maven run block' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match '\$\{SUPPRESSION_FILE\}'
  }
  It 'Uses ${ANALYZER_OVERRIDE} in the Maven run block' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match '\$\{ANALYZER_OVERRIDE\}'
  }
  It 'Uses ${DYN_SUPPRESSIONS_FILE} in the Maven run block' {
    $script:contents['reusable-owasp-check.yml'] | Should -Match '\$\{DYN_SUPPRESSIONS_FILE\}'
  }
}

Describe 'reusable-release-publish.yml - env-var wiring (Lote R)' {
  It 'Captures github.ref_name as REF_NAME' {
    $script:contents['reusable-release-publish.yml'] | Should -Match 'REF_NAME:\s+\${{ github\.ref_name'
  }
  It 'Captures github.ref_name as TAG_VERSION' {
    $script:contents['reusable-release-publish.yml'] | Should -Match 'TAG_VERSION:\s+\${{ github\.ref_name'
  }
  It 'Captures steps.visibility.outputs.value as PKG_VIS' {
    $script:contents['reusable-release-publish.yml'] | Should -Match 'PKG_VIS:\s+\${{ steps\.visibility\.outputs\.value'
  }
  It 'Captures github.event.repository.visibility as REPO_VIS' {
    $script:contents['reusable-release-publish.yml'] | Should -Match 'REPO_VIS:\s+\${{ github\.event\.repository\.visibility'
  }
  It 'Uses ${REF_NAME} in the Validate tag format step' {
    $script:contents['reusable-release-publish.yml'] | Should -Match '\$\{REF_NAME\}'
  }
  It 'Uses ${PKG_VIS} in the Publish step' {
    $script:contents['reusable-release-publish.yml'] | Should -Match '\$\{PKG_VIS\}'
  }
}

Describe 'reusable-build-matrix.yml - env-var wiring (Lote R)' {
  It 'Captures inputs.java-versions as VERSIONS' {
    $script:contents['reusable-build-matrix.yml'] | Should -Match 'VERSIONS:\s+\${{ inputs\.java-versions'
  }
  It 'Captures needs.matrix-build.result as MATRIX_RESULT' {
    $script:contents['reusable-build-matrix.yml'] | Should -Match 'MATRIX_RESULT:\s+\${{ needs\.matrix-build\.result'
  }
  It 'Uses ${VERSIONS} in the Matrix Summary step' {
    $script:contents['reusable-build-matrix.yml'] | Should -Match '\$\{VERSIONS\}'
  }
}

Describe 'nova-publish-aggregator/action.yml - env-var wiring (Lote R)' {
  It 'Captures inputs.build-tool as BUILD_TOOL' {
    $script:contents['nova-publish-aggregator/action.yml'] | Should -Match 'BUILD_TOOL:\s+\${{ inputs\.build-tool'
  }
  It 'Captures steps.visibility.outputs.value as PKG_VIS' {
    $script:contents['nova-publish-aggregator/action.yml'] | Should -Match 'PKG_VIS:\s+\${{ steps\.visibility\.outputs\.value'
  }
  It 'Uses ${BUILD_TOOL} in dispatch run blocks' {
    $script:contents['nova-publish-aggregator/action.yml'] | Should -Match '\$\{BUILD_TOOL\}'
  }
  It 'Uses ${PKG_VIS} in dispatch run blocks' {
    $script:contents['nova-publish-aggregator/action.yml'] | Should -Match '\$\{PKG_VIS\}'
  }
}

Describe 'nova-gather-facts/action.yml - env-var wiring (Lote R)' {
  It 'Captures inputs.version-source as VERSION_SOURCE' {
    $script:contents['nova-gather-facts/action.yml'] | Should -Match 'VERSION_SOURCE:\s+\${{ inputs\.version-source'
  }
  It 'Captures inputs.version-file as VERSION_FILE' {
    $script:contents['nova-gather-facts/action.yml'] | Should -Match 'VERSION_FILE:\s+\${{ inputs\.version-file'
  }
  It 'Captures inputs.fallback-version as FALLBACK_VERSION' {
    $script:contents['nova-gather-facts/action.yml'] | Should -Match 'FALLBACK_VERSION:\s+\${{ inputs\.fallback-version'
  }
  It 'Uses ${VERSION_SOURCE} in run blocks' {
    $script:contents['nova-gather-facts/action.yml'] | Should -Match '\$\{VERSION_SOURCE\}'
  }
  It 'Uses ${VERSION_FILE} in run blocks' {
    $script:contents['nova-gather-facts/action.yml'] | Should -Match '\$\{VERSION_FILE\}'
  }
}

Describe 'nova-setup-gpg/action.yml - env-var wiring (Lote R)' {
  It 'Captures inputs.gpg-signing-key-id as KEY_ID' {
    $script:contents['nova-setup-gpg/action.yml'] | Should -Match 'KEY_ID:\s+\${{ inputs\.gpg-signing-key-id'
  }
  It 'Captures inputs.gpg-signing-key as KEY' {
    $script:contents['nova-setup-gpg/action.yml'] | Should -Match 'KEY:\s+\${{ inputs\.gpg-signing-key'
  }
  It 'Captures inputs.gpg-signing-password as PASSWORD' {
    $script:contents['nova-setup-gpg/action.yml'] | Should -Match 'PASSWORD:\s+\${{ inputs\.gpg-signing-password'
  }
  It 'Uses ${KEY_ID} in git config run block' {
    $script:contents['nova-setup-gpg/action.yml'] | Should -Match '\$\{KEY_ID\}'
  }
  It 'Uses ${KEY} in import run block' {
    $script:contents['nova-setup-gpg/action.yml'] | Should -Match '\$\{KEY\}'
  }
  It 'Uses ${PASSWORD} in configure-git run block' {
    $script:contents['nova-setup-gpg/action.yml'] | Should -Match '\$\{PASSWORD\}'
  }
}

Describe 'nova-validate-build/action.yml - env-var wiring (Lote R)' {
  It 'Captures inputs.min-java-version as MIN_MAJOR' {
    $script:contents['nova-validate-build/action.yml'] | Should -Match 'MIN_MAJOR:\s+\${{ inputs\.min-java-version'
  }
  It 'Uses ${MIN_MAJOR} in the run block' {
    $script:contents['nova-validate-build/action.yml'] | Should -Match '\$\{MIN_MAJOR\}'
  }
}
