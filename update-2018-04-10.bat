@echo off
cd /d %~dp0
if exist "Stats\Fire*HashRate.txt" del "Stats\Fire*HashRate.txt"
if exist "Stats\BMiner*HashRate.txt" del "Stats\BMiner*HashRate.txt"
if exist "Stats\ClaymoreCpu*HashRate.txt" del "Stats\ClaymoreCpu*HashRate.txt"
