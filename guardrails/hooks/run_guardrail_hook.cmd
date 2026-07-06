@echo off
:: AI Agent Guardrail Hook Wrapper
:: Ensures fail-closed behavior: any Python failure (including Python not found)
:: becomes exit 2 (blocking) rather than exit 1 (non-blocking pass-through).
:: Claude Code hooks: exit 2 = block, exit 1 = non-blocking error (allow through).
python "%~dp0aiagent_guardrail_check.py" --mode claude-hook
if %ERRORLEVEL% equ 0 exit /b 0
exit /b 2
