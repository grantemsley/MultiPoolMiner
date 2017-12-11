@echo off
setx GPU_FORCE_64BIT_PTR 1
setx GPU_MAX_HEAP_SIZE 100
setx GPU_USE_SYNC_OBJECTS 1
setx GPU_MAX_ALLOC_PERCENT 100
setx GPU_SINGLE_ALLOC_PERCENT 100

powershell -noexit -executionpolicy bypass -windowstyle maximized -command "& .\multipoolminer.ps1"
pause