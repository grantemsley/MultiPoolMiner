setx GPU_FORCE_64BIT_PTR 1
setx GPU_MAX_HEAP_SIZE 100
setx GPU_USE_SYNC_OBJECTS 1
setx GPU_MAX_ALLOC_PERCENT 100
setx GPU_SINGLE_ALLOC_PERCENT 100

set bitcoinaddress=1Q24z7gHPDbedkaWDTFqhMF8g7iHMehsCb
set miningpoolhubuser=grantemsley
set workername=multipoolminer

set "command=& .\multipoolminer.ps1 -wallet %bitcoinaddress% -username %miningpoolhubuser% -workername %workername% -region europe -currency btc,usd,eur -type amd,nvidia,cpu -poolname miningpoolhub,miningpoolhubcoins,zpool,nicehash -algorithm cryptonight,decred,decrednicehash,ethash,ethash2gb,equihash,groestl,lbry,lyra2z,neoscrypt,pascal,sia,siaclaymore,sianicehash,sib -donate 24 -watchdog"
powershell -noexit -executionpolicy bypass -windowstyle maximized -command "%command%"

pause