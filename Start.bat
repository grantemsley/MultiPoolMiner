setx GPU_FORCE_64BIT_PTR 1
setx GPU_MAX_HEAP_SIZE 100
setx GPU_USE_SYNC_OBJECTS 1
setx GPU_MAX_ALLOC_PERCENT 100
setx GPU_SINGLE_ALLOC_PERCENT 100

set bitcoinaddress=1BLXARB3GbKyEg8NTY56me5VXFsX2cixFB
set miningpoolhubuser=grantemsley
set workername=multipoolminer

set "command=& .\multipoolminer.ps1 -wallet %bitcoinaddress% -username %miningpoolhubuser% -workername %workername% -region US -currency btc -type amd,nvidia,cpu -poolname miningpoolhub,miningpoolhubcoins,zpool -donate 24 -watchdog -verbose"
powershell -noexit -executionpolicy bypass -windowstyle maximized -command "%command%"

pause