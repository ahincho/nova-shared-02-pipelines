BeforeAll {
  $script:wfPath = Join-Path $PSScriptRoot '..\.github\workflows\reusable-ssh-deploy.yml'
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

  # Body of a key two levels under `inputs:` or `secrets:` (6 spaces).
  function Get-InputBlock([string] $text, [string] $name) {
    [regex]::Match($text, '(?ms)^      ' + [regex]::Escape($name) + ':\s*$(.*?)(?=^      \S|^    \S|^\S|^  \S)').Groups[1].Value
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

  # Literal text as a regex, so scripts can be matched without escaping by hand.
  function Esc([string] $text) { [regex]::Escape($text) }

  # Text of the comments at the left margin and of the description block, on
  # one line each, so a check does not depend on where a line was wrapped.
  function Get-Comments([string] $text) {
    (((($text -split "`r?`n") | Where-Object { $_ -match '^#' }) -replace '^#\s?', '') -join ' ') -replace '\s+', ' '
  }
  function Get-Description([string] $text) {
    [regex]::Match($text, '(?ms)^description: \|\s*\n(.*?)^on:').Groups[1].Value -replace '\s+', ' '
  }

  $script:steps = Get-Steps $script:wfText
  $script:runBlocks = Get-RunBlocks $script:wfText
}

Describe 'reusable-ssh-deploy.yml - trigger and interface' {
  It 'workflow file exists' {
    Test-Path -LiteralPath $script:wfPath | Should -BeTrue
  }

  It 'has the name and the description block of the other reusable workflows' {
    $script:wfText | Should -Match '(?m)^name: Reusable SSH Deploy\s*$'
    $script:wfText | Should -Match '(?m)^description: \|\s*$'
  }

  It 'is callable only as a reusable workflow' {
    $script:wfText | Should -Match '(?m)^on:\s*\n\s{2}workflow_call:'
    $script:wfText | Should -Not -Match '(?m)^  (push|pull_request|pull_request_target|schedule|workflow_dispatch|workflow_run|merge_group):' -Because 'the caller owns the triggers'
  }

  It 'declares the nine inputs with their types, requirement and defaults' {
    # name -> type, required, default (none for the ones the caller must give)
    $expected = [ordered]@{
      'sha'             = @('string', 'true',  $null)
      'component'       = @('string', 'false', "''")
      'artifact-name'   = @('string', 'true',  $null)
      'artifact-file'   = @('string', 'true',  $null)
      'host'            = @('string', 'true',  $null)
      'known-hosts'     = @('string', 'true',  $null)
      'ssh-user'        = @('string', 'true',  $null)
      'health-url'      = @('string', 'false', "''")
      'timeout-minutes' = @('number', 'false', '20')
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
    $section = [regex]::Match($script:wfText, '(?ms)^    inputs:\s*\n(.*?)^    secrets:').Groups[1].Value
    $names = @([regex]::Matches($section, '(?m)^      ([\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
    (($names | Sort-Object) -join ',') | Should -Be 'artifact-file,artifact-name,component,health-url,host,known-hosts,sha,ssh-user,timeout-minutes'
  }

  It 'declares ssh-key as its only secret, and it is required' {
    $section = [regex]::Match($script:wfText, '(?ms)^    secrets:\s*\n(.*?)(?=^\S)').Groups[1].Value
    $names = @([regex]::Matches($section, '(?m)^      ([\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
    ($names -join ',') | Should -Be 'ssh-key'
    (Get-InputBlock $script:wfText 'ssh-key') | Should -Match '(?m)^\s+required:\s*true\s*$'
  }

  It 'documents on the secret that the key is pinned to a forced command and has no passphrase' {
    $block = Get-InputBlock $script:wfText 'ssh-key'
    $block | Should -Match 'authorized_keys'
    $block | Should -Match 'forced\s+command'
    $block | Should -Match 'without a\s+passphrase'
  }

  It 'documents the first line sent, with and without a component' {
    (Get-InputBlock $script:wfText 'component') | Should -Match (Esc "'<component> <sha>' instead of '<sha>'")
    (Get-Description $script:wfText) | Should -Match (Esc 'when `component` is set, `<component> <sha>`')
  }
}

Describe 'reusable-ssh-deploy.yml - job hardening' {
  It 'grants the token read access to contents and actions and nothing else' {
    $block = [regex]::Match($script:wfText, '(?ms)^permissions:\s*\n(.*?)(?=^\S)').Groups[1].Value
    $pairs = @([regex]::Matches($block, '(?m)^  ([\w-]+):\s*(\S+)\s*$') | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value })
    (($pairs | Sort-Object) -join ',') | Should -Be 'actions=read,contents=read'
  }

  It 'tells the caller to grant those permissions' {
    (Get-Comments $script:wfText) | Should -Match (Esc 'IMPORTANT: the CALLER workflow must declare these two scopes')
  }

  It 'declares no concurrency of its own: that belongs to the caller' {
    $script:wfText | Should -Not -Match '(?m)^\s*concurrency:\s*$'
    (Get-Comments $script:wfText) | Should -Match (Esc 'one deploy at a time per environment, with cancel-in-progress: false')
  }

  It 'takes the timeout of the job from the timeout-minutes input' {
    $script:wfText | Should -Match '(?m)^    timeout-minutes:\s*\$\{\{ inputs\.timeout-minutes \}\}\s*$'
  }

  It 'runs its scripts with bash and no job-wide working-directory' {
    $defaults = [regex]::Match($script:wfText, '(?ms)^    defaults:\s*\n(.*?)(?=^    \S|^\S|^  \S)').Groups[1].Value
    $defaults | Should -Match '(?m)^\s+shell:\s*bash\s*$'
    $defaults | Should -Not -Match 'working-directory'
  }

  It 'never checks out the repository: a job that holds a deploy key runs no code of the repository' {
    $script:wfText | Should -Not -Match 'actions/checkout'
  }
}

Describe 'reusable-ssh-deploy.yml - SHA pinning (Lote Q)' {
  It 'pins every uses: ref to a 40-char commit SHA with its version in a comment' {
    $refs = [regex]::Matches($script:wfText, '(?m)^\s*(?:-\s*)?uses:\s*(\S+)(.*)$')
    $refs.Count | Should -BeGreaterOrEqual 1
    foreach ($m in $refs) {
      $m.Groups[1].Value | Should -Match '@[0-9a-f]{40}$' -Because "'$($m.Groups[1].Value)' must be pinned to a commit SHA"
      $m.Groups[2].Value | Should -Match '#\s*v\d+\.\d+\.\d+' -Because "'$($m.Groups[1].Value)' must name its version"
    }
  }

  It 'runs no third-party code besides actions/download-artifact' {
    $actions = @([regex]::Matches($script:wfText, '(?m)^\s*(?:-\s*)?uses:\s*([^@\s]+)@') | ForEach-Object { $_.Groups[1].Value })
    ($actions -join ',') | Should -Be 'actions/download-artifact' -Because 'every action in the job runs next to the deploy key'
  }
}

Describe 'reusable-ssh-deploy.yml - validation of the inputs' {
  It 'is the first step, so nothing is downloaded or written before the inputs are checked' {
    $script:steps.Count | Should -BeGreaterThan 0
    $script:steps[0] | Should -Not -Match '(?m)^\s+uses:'
    (Find-Step 'uses:\s*actions/download-artifact@') | Should -BeGreaterThan 0
    (Find-Step 'printf .%s\\n. "\$SSH_KEY"') | Should -BeGreaterThan 0
  }

  It 'requires sha to be a full 40-character lowercase hex SHA' {
    $script:steps[0] | Should -Match (Esc '[[ $SHA =~ ^[0-9a-f]{40}$ ]] || fail "sha must be a full 40-character lowercase hex commit SHA, not ''$SHA''."')
  }

  It 'requires component, when it is set, to match ^[a-z][a-z0-9-]*$' {
    $script:steps[0] | Should -Match (Esc 'if [ -n "$COMPONENT" ]; then')
    $script:steps[0] | Should -Match (Esc '[[ $COMPONENT =~ ^[a-z][a-z0-9-]*$ ]] || fail "component must be lowercase letters, digits and hyphens, starting with a letter, not ''$COMPONENT''."')
  }

  It 'accepts an empty component, which keeps the SHA-only first line' {
    $block = [regex]::Match($script:steps[0], '(?ms)if \[ -n "\$COMPONENT" \]; then\s*\n(.*?)\n\s+fi').Groups[1].Value
    $block | Should -Not -BeNullOrEmpty -Because 'the component check must sit inside the if that tests that it is set'
    $block | Should -Match 'COMPONENT =~'
  }

  It 'keeps the user and the host from starting with a dash, which ssh would read as an option' {
    $script:steps[0] | Should -Match (Esc '[[ $SSH_USER =~ ^[A-Za-z_][A-Za-z0-9._-]*$ ]] || fail')
    $script:steps[0] | Should -Match (Esc '[[ $HOST =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || fail')
  }

  It 'fails on an empty known-hosts and on an empty ssh-key, naming the secret' {
    $script:steps[0] | Should -Match (Esc '[ -n "$KNOWN_HOSTS" ] || fail "known-hosts is empty')
    $script:steps[0] | Should -Match (Esc '[ -n "$SSH_KEY" ] || fail "The ssh-key secret is empty.')
  }

  It 'accepts only an http or https health-url, and only when there is one' {
    $script:steps[0] | Should -Match (Esc 'if [ -n "$HEALTH_URL" ]; then')
    $script:steps[0] | Should -Match (Esc '[[ $HEALTH_URL =~ ^https?://[^[:space:]]+$ ]] || fail "health-url must be an http or https URL."')
  }

  It 'fails every check with an ::error:: through one function that stops the step' {
    $script:steps[0] | Should -Match (Esc 'fail() { echo "::error::$1 Not deploying."; exit 1; }')
  }

  It 'receives every value through env' {
    $expected = [ordered]@{
      'SHA'         = 'inputs.sha'
      'COMPONENT'   = 'inputs.component'
      'HOST'        = 'inputs.host'
      'KNOWN_HOSTS' = 'inputs.known-hosts'
      'SSH_USER'    = 'inputs.ssh-user'
      'HEALTH_URL'  = 'inputs.health-url'
      'SSH_KEY'     = 'secrets.ssh-key'
    }
    foreach ($name in $expected.Keys) {
      $script:steps[0] | Should -Match ('(?m)^\s+' + $name + ':\s*\$\{\{ ' + [regex]::Escape($expected[$name]) + ' \}\}\s*$') -Because "$name must come from $($expected[$name]) through env"
    }
  }
}

Describe 'reusable-ssh-deploy.yml - the SSH key' {
  It 'reaches only the two steps that need it, as a step-level env entry' {
    $lines = @((($script:wfText -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) | Where-Object { $_ -match 'secrets\.' })
    $lines.Count | Should -Be 2 -Because 'the check that it is not empty and the step that writes it'
    foreach ($line in $lines) {
      $line | Should -Match '^ {10}SSH_KEY:\s*\$\{\{ secrets\.ssh-key \}\}\s*$' -Because 'a secret reaches only the step that needs it, through env, so no other step or action can read it'
    }
  }

  It 'is only tested for emptiness or written to its file, never printed' {
    foreach ($block in $script:runBlocks) {
      $rest = $block -replace [regex]::Escape('[ -n "$SSH_KEY" ]'), '' -replace [regex]::Escape("printf '%s\n' `"`$SSH_KEY`" | tr -d '\r' > ~/.ssh/deploy"), ''
      $rest | Should -Not -Match 'SSH_KEY' -Because 'the private key must not reach a log or a command line'
    }
  }

  It 'is written for the job only, in a folder of 0700 and a file of 0600' {
    $install = $script:steps[(Find-Step 'printf .%s\\n. "\$SSH_KEY"')]
    $install | Should -Match '(?m)^\s+umask 077\s*$'
    $install | Should -Match '(?m)^\s+chmod 700 ~/\.ssh\s*$'
    $install | Should -Match '(?m)^\s+chmod 600 ~/\.ssh/deploy\s*$'
    $install.IndexOf('umask 077', [StringComparison]::Ordinal) | Should -BeLessThan $install.IndexOf('> ~/.ssh/deploy', [StringComparison]::Ordinal) -Because 'the file must never exist with looser permissions'
  }

  It 'keeps the pinned host key in a file of its own and never touches ~/.ssh/known_hosts' {
    $install = $script:steps[(Find-Step 'printf .%s\\n. "\$SSH_KEY"')]
    $install | Should -Match (Esc "printf '%s\n' `"`$KNOWN_HOSTS`" | tr -d '\r' > ~/.ssh/deploy_known_hosts")
    $script:wfText | Should -Not -Match '~/\.ssh/known_hosts'
    $script:wfText | Should -Not -Match '\$HOME/\.ssh/known_hosts'
  }

  It 'drops the carriage returns of a key or a host line pasted from Windows' {
    $install = $script:steps[(Find-Step 'printf .%s\\n. "\$SSH_KEY"')]
    ([regex]::Matches($install, [regex]::Escape("tr -d '\r'"))).Count | Should -Be 2
  }

  It 'is written after the artifact file is checked and before it is sent' {
    $check = Find-Step 'realpath -e'
    $install = Find-Step 'printf .%s\\n. "\$SSH_KEY"'
    $send = Find-Step '\| ssh '
    $check | Should -BeGreaterThan 0
    $install | Should -BeGreaterThan $check
    $send | Should -BeGreaterThan $install
  }

  It 'is deleted by the last step, which runs even when the deploy fails' {
    $last = $script:steps[$script:steps.Count - 1]
    $last | Should -Match '(?m)^\s+if:\s*always\(\)\s*$'
    $last | Should -Match (Esc 'rm -f ~/.ssh/deploy ~/.ssh/deploy_known_hosts')
    $last | Should -Not -Match 'secrets\.'
  }
}

Describe 'reusable-ssh-deploy.yml - the artifact' {
  It 'downloads the artifact of this run by name into a folder of the runner temp' {
    $download = $script:steps[(Find-Step 'uses:\s*actions/download-artifact@')]
    $download | Should -Match '(?m)^\s+name:\s*\$\{\{ inputs\.artifact-name \}\}\s*$'
    $download | Should -Match '(?m)^\s+path:\s*\$\{\{ runner\.temp \}\}/deploy-artifact\s*$'
    $download | Should -Not -Match 'github-token|run-id|repository' -Because 'the artifact belongs to the run that calls this workflow'
  }

  It 'reads the file from that same folder in the check and in the send steps' {
    foreach ($pattern in @('realpath -e', '\| ssh ')) {
      $step = $script:steps[(Find-Step $pattern)]
      $step | Should -Match '(?m)^\s+ARTIFACT_DIR:\s*\$\{\{ runner\.temp \}\}/deploy-artifact\s*$'
      $step | Should -Match '(?m)^\s+ARTIFACT_FILE:\s*\$\{\{ inputs\.artifact-file \}\}\s*$'
    }
  }

  It 'fails when the file is not in the artifact, and lists what is there' {
    $check = $script:steps[(Find-Step 'realpath -e')]
    $check | Should -Match (Esc 'if [ ! -f "$file" ]; then')
    $check | Should -Match (Esc "find `"`$ARTIFACT_DIR`" -type f -printf '  %P\n'")
    $check | Should -Match (Esc 'fail "File ''$ARTIFACT_FILE'' is not in artifact ''$ARTIFACT_NAME''."')
  }

  It 'resolves the path and fails when it ends up outside the artifact' {
    $check = $script:steps[(Find-Step 'realpath -e')]
    $check | Should -Match (Esc 'real=$(realpath -e -- "$file")')
    $check | Should -Match (Esc 'root=$(realpath -e -- "$ARTIFACT_DIR")')
    $check | Should -Match (Esc '"$root"/*) ;;')
    $check | Should -Match (Esc 'fail "File ''$ARTIFACT_FILE'' resolves outside artifact ''$ARTIFACT_NAME''." ;;')
  }
}

Describe 'reusable-ssh-deploy.yml - sending' {
  It 'runs the validation, the download, the file check, the key, the send, the health check and the cleanup, in that order' {
    $patterns = [ordered]@{
      'validation'   = 'fail\(\) \{ echo'
      'download'     = 'uses:\s*actions/download-artifact@'
      'file check'   = 'realpath -e'
      'key'          = 'printf .%s\\n. "\$SSH_KEY"'
      'send'         = '\| ssh '
      'health check' = 'curl -fsS'
      'cleanup'      = 'rm -f ~/\.ssh/deploy '
    }
    $previous = -1
    foreach ($name in $patterns.Keys) {
      $index = Find-Step $patterns[$name]
      $index | Should -BeGreaterThan $previous -Because "the $name step must exist and come after the one before it"
      $previous = $index
    }
    $script:steps.Count | Should -Be 7
  }

  It 'sends the first line and then the bytes of the file through one pipe into ssh' {
    $send = $script:steps[(Find-Step '\| ssh ')]
    $send | Should -Match (Esc "{ printf '%s\n' `"`$header`"; cat `"`$file`"; } | ssh ")
  }

  It 'pins the key, the options and the host key, and passes no remote command' {
    $send = $script:steps[(Find-Step '\| ssh ')]
    $send | Should -Match (Esc "| ssh -i ~/.ssh/deploy -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o `"UserKnownHostsFile=`$HOME/.ssh/deploy_known_hosts`" -T `"`$SSH_USER@`$HOST`"")
    $send | Should -Match '(?m)"\$SSH_USER@\$HOST"\s*$' -Because 'the server runs its forced command whatever the client asks for, so nothing follows the destination'
  }

  It 'sends only the SHA when component is empty, and the component and the SHA when it is set' {
    $send = $script:steps[(Find-Step '\| ssh ')]
    $send | Should -Match '(?ms)if \[ -n "\$COMPONENT" \]; then\s*\n\s+header="\$COMPONENT \$SHA"\s*\n\s+else\s*\n\s+header="\$SHA"\s*\n\s+fi'
  }

  It 'hands the SHA, the component, the host and the user to the send step through env' {
    $send = $script:steps[(Find-Step '\| ssh ')]
    $send | Should -Match '(?m)^\s+SHA:\s*\$\{\{ inputs\.sha \}\}\s*$'
    $send | Should -Match '(?m)^\s+COMPONENT:\s*\$\{\{ inputs\.component \}\}\s*$'
    $send | Should -Match '(?m)^\s+HOST:\s*\$\{\{ inputs\.host \}\}\s*$'
    $send | Should -Match '(?m)^\s+SSH_USER:\s*\$\{\{ inputs\.ssh-user \}\}\s*$'
  }

  It 'checks the health URL only when there is one, retrying with curl' {
    $health = $script:steps[(Find-Step 'curl -fsS')]
    $health | Should -Match '(?m)^\s+if:\s*inputs\.health-url != ''''\s*$'
    $health | Should -Match '(?m)^\s+HEALTH_URL:\s*\$\{\{ inputs\.health-url \}\}\s*$'
    $health | Should -Match (Esc 'curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$HEALTH_URL"')
  }

  It 'never interpolates a ${{ }} expression inside a run block' {
    $script:runBlocks.Count | Should -Be 6
    foreach ($block in $script:runBlocks) {
      $block | Should -Not -Match '\$\{\{' -Because 'inputs, secrets and context values must reach the script through env'
    }
  }
}
