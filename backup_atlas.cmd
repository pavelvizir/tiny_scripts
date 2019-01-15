if not exist "%~dp07za.exe" exit /b
if "%2"=="" exit /b
rem set name=jira | set name=confluence
set name=%1
rem set backup_type=FULL | set backup_type=DIFF
rem set backup_type=FULL
set backup_type=%2
set dir_to_backup=C:\Program Files\Atlassian
set dir_to_store_backups=C:\Backup
set sql_backup_dir=\\sqlserver\C$\Backup\instance\%name%db\%backup_type%
set zip_parameters=-bb0 -bd -t7z -ssw -y -mmt=6 -mx3 -m0=lzma2:d16:fb=64
set network_backup_dir=\\arch\backup\Jira
set days_to_keep_backups=70
set /a cleanup_time=170
if "%backup_type%"=="FULL" set /a cleanup_time=%cleanup_time%*2
for /f %%a in ('wmic path win32_localtime get year^,month^,day^,hour^,minute /value ^| findstr ^= ') do (set %%a)
if %month% lss 10 set month=0%month%
if %day% lss 10 set day=0%day%
if %hour% lss 10 set hour=0%hour%
if %minute% lss 10 set minute=0%minute%
set date_string=%year%-%month%-%day%_%hour%-%minute%
sqlcmd -E -S tcp:sqlserver,37821 -d Maintenance -Q "EXECUTE dbo.DatabaseBackup @Databases = '%name%db', @Directory = 'C:\Backup', @BackupType = '%backup_type%', @Verify = 'Y', @Compress = 'N', @CheckSum = 'Y', @CleanupTime = %cleanup_time%, @LogToTable = 'Y'" -b
for /f %%i in ('dir /A:-D /B /O:-D /T:W "%sql_backup_dir%"') do (
set sql_backup=%%i
goto :next_1
)
:next_1
"%~dp07za.exe" a "%dir_to_store_backups%\%name%_db_%backup_type%_%date_string%.7z" "%sql_backup_dir%\%sql_backup%" %zip_parameters%
if "%backup_type%"=="FULL" (
"%~dp07za.exe" a "%dir_to_store_backups%\%name%_dir_%backup_type%_%date_string%.7z" "%dir_to_backup%" -ms=off %zip_parameters%
) else (
for /f %%i in ('dir /A:-D /B /O:-D /T:W "%dir_to_store_backups%\%name%_dir_FULL_*.7z"') do (
set last_full_backup=%%i
goto :next_2
)
:next_2
"%~dp07za.exe" u "%dir_to_store_backups%\%last_full_backup%" "%dir_to_backup%" %zip_parameters% -u- -up0q3r2x2y2z0w2!"%dir_to_store_backups%\%name%_dir_%backup_type%_%date_string%.7z"
echo To unpack run:
echo 	"%~dp07za.exe".exe x "%dir_to_store_backups%\%last_full_backup%" -o"%dir_to_backup%"
echo 	"%~dp07za.exe".exe x "%dir_to_store_backups%\%name%_dir_%backup_type%_%date_string%.7z" -aoa -y -o"%dir_to_backup%"
)
"%~dp07za.exe" a "%network_backup_dir%\%name%_%backup_type%_%date_string%.7z" "%dir_to_store_backups%\%name%_db_%backup_type%_%date_string%.7z" "%dir_to_store_backups%\%name%_dir_%backup_type%_%date_string%.7z" -t7z -mx=0 -y
forfiles /P "%dir_to_store_backups%" /M *.7z /d -%days_to_keep_backups% /c "cmd /c del /f /q @file"
exit /b