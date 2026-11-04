@echo off
py -3 "%~dp0ExportarDiario.py"
if errorlevel 1 (
  echo.
  echo No se pudo iniciar Python. Instala Python 3 desde https://www.python.org/downloads/
  pause
)
