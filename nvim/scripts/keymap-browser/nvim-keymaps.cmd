@echo off
setlocal
if defined NVIM_KEYMAPS_PYTHON (
  "%NVIM_KEYMAPS_PYTHON%" -B "%~dp0server.py" %*
  exit /b
)
where py >nul 2>&1
if not errorlevel 1 (
  py -3 -B "%~dp0server.py" %*
) else (
  python -B "%~dp0server.py" %*
)
