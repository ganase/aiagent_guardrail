param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$ArgsList
)
$ErrorActionPreference = "Stop"
$homeDir = $env:AIAGENT_GUARDRAIL_HOME
if (-not $homeDir) { $homeDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$checker = Join-Path $homeDir "hooks\aiagent_guardrail_check.py"
$cmd = "pip " + ($ArgsList -join " ")
python $checker --command $cmd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python -m pip @ArgsList
exit $LASTEXITCODE
