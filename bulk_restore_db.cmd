@echo off
rem If backup's year is different from current year then uncomment the next line and define the backup's year there.
rem set year=2016 

rem Following two variables are being set further for few known hosts (:set_vars_for_known_hosts)
set sql_data_dir=C:\Program Files\Microsoft SQL Server\MSSQL10_50.MSSQLSERVER\MSSQL\DATA
set sqlcmd_string=sqlcmd -E -S localhost
set db_file_maxsize=UNLIMITED
set db_file_flegrowth=65536KB
set check_restore_status_string=RESTORE DATABASE successfully processed
set shrink_percentage=5
rem Following line sets shrink mode, change it to "NOTRUNCATE" for a safe shrink, leave empty for dangerous one :-)
set shrink_mode=
set cas_factor=3/2
rem Following line sets script behaviour in the end. If not set shows short log with pager(more) and pauses at the end. Set to 1 in case of running unattended.
set is_unattended=
set db_reindex_exceptions=

:set_vars_for_known_hosts
for /f %%j in ('hostname') do set hostname=%%j
if "%hostname%"=="test" (
set sql_data_dir=C:\Program Files\Microsoft SQL Server\MSSQL10_50.MSSQLSERVER\MSSQL\DATA
set sqlcmd_string=sqlcmd -E -S localhost
)

title PLEASE_WAIT... & prompt .
if "%1"=="log" goto :main
title Running maintenance tasks...
if exist "%~dpn0.log" (type "%~dpn0.log" >> "%~dpn0.old"
del /f /q  "%~dpn0.log")
call "%~f0" log >>"%~dpn0.log" 2<&1
@echo off
call :after_launch>>"%~dpn0_after_launch.log" 2<&1
echo CREATING FULL LOG...>>"%~dpn0_logs\%~n0_after_after_launch.log" 2<&1
echo    Details in "%~dpn0_logs\%~n0_after_after_launch.log".>>"%~dpn0_logs\%~n0_after_after_launch.log" 2<&1
robocopy /MOV "%~dp0\" "%~dpn0_logs\\" *.log>>"%~dpn0_logs\%~n0_after_after_launch.log" 2<&1
call :create_full_log>>"%~dpn0_logs\%~n0_after_after_launch.log" 2<&1
if not defined is_unattended (
title Completed. Final log:
chcp 866 >nul 2<&1
color 0a
type "%~dpn0_logs\%~n0%1_clean.log" | more
pause)
exit /B %exit_code%

:after_launch
@echo on
call :make_clean_log
if not exist "%~dpn0_logs" mkdir "%~dpn0_logs"
call :create_old_log
call :truncate_compress_logs
robocopy /MOV "%~dp0\" "%~dpn0_logs\\" *.sql
robocopy /MOV "%~dp0\" "%~dpn0_logs\\" *.old
robocopy /MOV "%~dp0\" "%~dpn0_logs\\" *.log
robocopy "%~dp0\" "%~dpn0_logs\\" %~nx0
GOTO :EOF

:make_clean_log
if exist "%~dpn0%1_clean.log" type "%~dpn0%1_clean.log" >> "%~dpn0%1_clean.old"
if exist "%~dpn0%1_clean.old" echo. >> "%~dpn0%1_clean.old"
if exist "%~dpn0%1_clean.log" del /f /q "%~dpn0%1_clean.log"
for /f "delims=№" %%G in ('type "%~dpn0%1.log" ^| findstr /v "^\..*"') do echo %%G >> "%~dpn0%1_clean.log"
GOTO :EOF

:run_script
echo      Processing database [%1]...
if not defined position_in_list (set /a position_in_list=1) else (set /a position_in_list=%position_in_list%+1)
call :log_and_time_2 :run_script_restore %1
@echo off
call :check_restore_status %1
if "%restore_status%"=="0" (
call :log_and_time_2 :run_script_permissions %1
call :log_and_time_2 :run_script_reindex_shrink %1
) else (
echo ACHTUNG!!! DATABASE %1 NOT RESTORED! PANIC!!!
)
call :log_and_time_2 :clean_restored_db_files %1
@echo on
GOTO :EOF

:run_script_restore
start ":run_script_restore %1" /min /wait %sqlcmd_string% -i "%~dpn0_%1_restore.sql" -o "%~dpn0_%1_restore.log"
GOTO :EOF

:run_script_permissions
start ":run_script_permissions %1" /min /wait %sqlcmd_string% -i "%~dpn0_%1_permissions.sql" -o "%~dpn0_%1_permissions.log"
GOTO :EOF

:run_script_reindex_shrink
for %%t in (%db_reindex_exceptions%) do if "%1" == "%%t" (
echo Database %1 is in the list [db_reindex_exceptions] therefore script "%~dpn0_%1_reindex_shrink.sql" was not executed.>"%~dpn0_%1_reindex_shrink.log"
echo        NOT EXECUTED.
GOTO :EOF)
start ":run_script_reindex_shrink %1" /min /wait %sqlcmd_string% -i "%~dpn0_%1_reindex_shrink.sql" -o "%~dpn0_%1_reindex_shrink.log"
GOTO :EOF

:clean_restored_db_files
call :delete_with_log %1.bak
echo ----- Moving archived database backup file to "%~dpn0_processed_archives" ...
if not exist "%~dpn0_processed_archives" mkdir "%~dpn0_processed_archives"
for /f "tokens=%position_in_list% delims=," %%x in ("%long_name_list%") do (
move /Y "%~dp0%%x" "%~dpn0_processed_archives">nul 2<&1
if %ERRORLEVEL% EQU 0 (echo       + OK!) else (echo       - FAIL!)
)
GOTO :EOF

:clean_garbage
@echo off
dir /B /A:-D *.bak >nul 2<&1
if %ERRORLEVEL% EQU 0 (echo ----- Found garbage. Moving to "%~dpn0_garbage"...
robocopy /MOV "%~dp0\" "%~dpn0_garbage\\" *.bak >nul 2<&1
)
dir /B /A:-D *.7z >nul 2<&1
if %ERRORLEVEL% EQU 0 (echo ----- Found garbage. Moving to "%~dpn0_garbage"...
robocopy /MOV "%~dp0\" "%~dpn0_garbage\\" *.7z >nul 2<&1
)
@echo on
GOTO :EOF

:string_to_gbytes
set cas_gbytes_dirty=
set cas_bytes=%1
set /a cas_gbytes_dirty=%cas_bytes:~0,-9% >nul 2<&1
if not defined cas_gbytes_dirty set /a cas_gbytes_dirty=1
set /a cas_gbytes=%cas_gbytes_dirty%*93/100
if %cas_gbytes%==0 set /a cas_gbytes=1
GOTO :EOF

:check_available_storage
for /f "tokens=3 delims=," %%a in ('wmic logicaldisk get freespace^,deviceid ^/format:csv ^| findstr %~d0') do call :string_to_gbytes %%a
set /a cas_disk_free_space=%cas_gbytes%
@echo off
if %cas_disk_free_space% LSS %cas_space_required% (
echo NOT ENOUGH SPACE!
echo  Need [%cas_space_required%] GB of space, but only [%cas_disk_free_space%] GB available.
echo Aborting!
echo.
set /a exit_code=1
@echo on && exit /B %exit_code%
)
@echo on && GOTO :EOF

:uncompress_backup_archives
for %%u in (%long_name_list%) do call :get_backup_size_from_archive %%u
call :check_available_storage
if defined exit_code exit /B %exit_code%
for %%u in (%long_name_list%) do call :log_and_time_2 :uncompress_backup %%u
GOTO :EOF

:uncompress_backup
"%~dp07za.exe" e -y %1>> "%~dpn0_uncompress.log" 2<&1
if %ERRORLEVEL% EQU 0 (echo       + OK!) else (echo       - FAIL!)
GOTO :EOF

:log_and_time_2
echo ----- Started %* on %time%.
set log_and_time_2_title=%2
if defined log_and_time_2_title set log_and_time_2_title=[%log_and_time_2_title%]
title Running %1 %log_and_time_2_title%
set log_and_time_2_title=
call %*
echo ----- Finished %* on %time%.
GOTO :EOF

:delete_with_log
echo ----- Trying to delete file %1.
del /f /q "%1" >nul 2<&1
if exist "%1" (echo  - Error: File was not deleted.) else (echo       + OK!)
GOTO :EOF

:get_backup_size_from_archive
for /f "tokens=3" %%i in ('7za.exe l -slt %1 ^| findstr ^^^^Size') do call :string_to_gbytes %%i
if defined cas_space_required (set /a cas_space_required=%cas_space_required% + %cas_gbytes%*%cas_factor%) else (set /a cas_space_required=%cas_gbytes%*%cas_factor%)
GOTO :EOF

:check_restore_status
findstr "%check_restore_status_string%" "%~dpn0_%1_restore.log" >nul 2<&1
for /f "delims=?" %%o in ('%sqlcmd_string% -s "," -h -1 -W -Q "if exists (SELECT * FROM [msdb].[dbo].[restorehistory] U WHERE DATEDIFF(hour, U.restore_date, GETDATE()) <=1 and destination_database_name='%1') begin; select 0; end"') do if "%%o"=="%ERRORLEVEL%" (
set restore_status=0
GOTO :EOF)
set restore_status=
GOTO :EOF

:add_go_after
@echo off
call %*
echo GO
GOTO :EOF

:gen_db_permissions
echo USE %1>%2
echo GO>>%2
set sqlcmd_string_gen_permissions=%sqlcmd_string% -h -1 -W -Q "use %1; select 'if not exists(select name from sys.database_principals where name = ''' + users.name + ''') BEGIN CREATE USER [' + users.name+ '] FOR LOGIN [' + users.name + '] END --execute'  from sys.database_principals users inner join sys.database_role_members link on link.member_principal_id = users.principal_id inner join sys.database_principals roles on roles.principal_id = link.role_principal_id where users.name != 'dbo'"
for /f "delims=?" %%y in ('%sqlcmd_string_gen_permissions%') do echo %%y | findstr execute >> %2
echo GO>>%2
set sqlcmd_string_gen_permissions=%sqlcmd_string% -h -1 -W -Q "use %1; select 'execute sp_addrolemember ''' + roles.name + ''', ''' + users.name + '''' from sys.database_principals users inner join sys.database_role_members link on link.member_principal_id = users.principal_id inner join sys.database_principals roles on roles.principal_id = link.role_principal_id where users.name != 'dbo'"
for /f "delims=?" %%y in ('%sqlcmd_string_gen_permissions%') do echo %%y | findstr execute >> %2
echo GO>>%2
GOTO :EOF

:gen_name_list_prep
@echo off
setlocal
set name_long=%1
call set name_tail=%%name_long:*_%year%_=%%
call set name_short=%%name_long:_%year%_%name_tail%=%%
for %%z in (%database_list%) do if "%%z"=="%name_short%" (
endlocal
call :gen_name_list "%name_short%"
@echo on && GOTO :EOF)
@echo on && GOTO :EOF

:gen_database_list
if not defined database_list (set database_list=%1) else (call set database_list=%database_list%,%1)
goto :EOF

:gen_restore_script
set db_name=%1
for /L %%a in (1,1,3) do set move_string_%%a=
if not exist "%~dp0%db_name%.bak" echo Error: File "%db_name%.bak" not found. && GOTO :EOF
for /f "tokens=1,7 delims=," %%i in ('%sqlcmd_string% -s "," -h -1 -W -Q "set nocount on; IF DB_ID('%db_name%') IS NOT NULL exec sp_executesql N'restore filelistonly from disk=''%~dp0%db_name%.bak''';"') do call :gen_move_strings %%i %%j
@echo off
if defined move_string_1 if defined move_string_2 (
if not exist %~dpn0_%1_restore.sql call :add_go_after echo USE MASTER;SET LANGUAGE us_english;> %~dpn0_%1_restore.sql
call :add_go_after echo ALTER DATABASE [%db_name%] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;>> %~dpn0_%1_restore.sql
call :add_go_after echo RESTORE DATABASE [%db_name%] FROM DISK = N'%~dp0%db_name%.bak' WITH FILE = 1, %move_string_1% %move_string_2% %move_string_3% NOUNLOAD, REPLACE, STATS = 10>> %~dpn0_%1_restore.sql
call :add_go_after echo ALTER DATABASE [%db_name%] SET RECOVERY SIMPLE WITH NO_WAIT>> %~dpn0_%1_restore.sql
for /L %%x in (4,1,9) do if defined move_string_%%x call :add_go_after :move_string_echo move_string_%%x>> %~dpn0_%1_restore.sql
call :add_go_after echo ALTER DATABASE [%db_name%] SET MULTI_USER;>> %~dpn0_%1_restore.sql
call :gen_db_permissions %db_name% "%~dpn0_%1_permissions.sql"
call :gen_sql_reindex_shrink %db_name% "%~dpn0_%1_reindex_shrink.sql"
)
@echo on
GOTO :EOF

:gen_move_strings
@echo off
if %2 == 1 (
set move_string_1=MOVE N'%1' TO N'%sql_data_dir%\%db_name%.mdf',
set move_string_4=ALTER DATABASE [%db_name%] MODIFY FILE ( NAME = N'%1', MAXSIZE = %db_file_maxsize%, FILEGROWTH = %db_file_flegrowth% ^)
set move_string_5=ALTER DATABASE [%db_name%] MODIFY FILE ( NAME = N'%1', NEWNAME = N'%db_name%_data' ^)

)
if %2 == 2 (
set move_string_2=MOVE N'%1' TO N'%sql_data_dir%\%db_name%.ldf',
set move_string_6=ALTER DATABASE [%db_name%] MODIFY FILE ( NAME = N'%1', MAXSIZE = %db_file_maxsize%, FILEGROWTH = %db_file_flegrowth% ^)
set move_string_7=ALTER DATABASE [%db_name%] MODIFY FILE ( NAME = N'%1', NEWNAME = N'%db_name%_log' ^)
)
if %2 == 3 (
set move_string_3=MOVE N'%1' TO N'%sql_data_dir%\%db_name%.ndf',
set move_string_8=ALTER DATABASE [%db_name%] MODIFY FILE ( NAME = N'%1', MAXSIZE = %db_file_maxsize%, FILEGROWTH = %db_file_flegrowth% ^)
set move_string_9=ALTER DATABASE [%db_name%] MODIFY FILE ( NAME = N'%1', NEWNAME = N'%db_name%_secondary' ^)
)
@echo on
GOTO :EOF

:move_string_echo
call echo %%%1%%
GOTO :EOF

:gen_name_list
set name_short=%1
if defined name_list for %%t in (%name_list%) do if "%%t"==%1 GOTO :EOF
if not defined name_list (call set name_list=%name_short:"=%) else (call set name_list=%name_list%,%name_short:"=%)
for /f %%i in ('dir /B /A:-D /O:N /T:W %name_short:"=%_%year%_*.7z') do call set proper_name_long=%%i
if not defined long_name_list (set long_name_list="%proper_name_long%") else (set long_name_list=%long_name_list%,"%proper_name_long%")
GOTO :EOF

:gen_sql_reindex_shrink
@echo off
rem npp ^(.+)$ echo \1
echo use %1 > %2
echo -- Дефрагментация БД без сжатия >> %2
echo GO >> %2
echo. >> %2
echo declare @NameDB nvarchar(128) = db_name() >> %2
echo print convert(varchar(30), getdate(), 121) + ' SHRINKDATABASE {NOTRUNCATE} ...' >> %2
echo. >> %2
echo DBCC SHRINKDATABASE(@NameDB, %shrink_string%) WITH NO_INFOMSGS >> %2
echo. >> %2
echo GO >> %2
echo print convert(varchar(30), getdate(), 121) + ' REINDEX ...' >> %2
echo declare @cmdSQL varchar(max) >> %2
echo. >> %2
echo set @cmdSQL = '' >> %2
echo select @cmdSQL += ' >> %2
echo                     print convert(varchar(30), getdate(), 121) + ''    -' + quotename(schema_name(O.schema_id)) + '.' + quotename(O.name) + '.' + quotename(I.name) + '''  >> %2
echo                     ALTER INDEX ' + quotename(I.name) + '  >> %2
echo                         ON ' + quotename(schema_name(O.schema_id)) + '.' + quotename(O.name) + ' REBUILD PARTITION = ALL  >> %2
echo                         WITH (  >> %2
echo                                 PAD_INDEX  = OFF >> %2
echo                                ,STATISTICS_NORECOMPUTE  = OFF >> %2
echo                                ,ALLOW_ROW_LOCKS  = ON >> %2
echo                                ,ALLOW_PAGE_LOCKS  = ON >> %2
echo                                ,ONLINE = OFF >> %2
echo                                ,SORT_IN_TEMPDB = ON >> %2
echo                              ) >> %2
echo                     '   >> %2
echo     from sys.indexes I >> %2
echo         inner join sys.objects O on O.object_id = I.object_id >> %2
echo     where I.type_desc in ('CLUSTERED', 'NONCLUSTERED') and >> %2
echo           O.type = 'U' >> %2
echo. >> %2
echo exec (@cmdSQL) >> %2
echo GO >> %2
echo. >> %2
echo print convert(varchar(30), getdate(), 121) + ' UPDATE STATISTICS ...' >> %2
echo declare @cmdSQL nvarchar(max) >> %2
echo select @cmdSQL = '' >> %2
echo. >> %2
echo select @cmdSQL += ' >> %2
echo                     print convert(varchar(30), getdate(), 121) + ''    -' + quotename(schema_name(O.schema_id)) + '.' + quotename(O.name) + ''' >> %2
echo                     update statistics ' + quotename(schema_name(O.schema_id)) + '.' + quotename(O.name) + ' >> %2
echo                         with fullscan >> %2
echo                   ' >> %2
echo     from sys.objects O >> %2
echo     where type = 'U' >> %2
echo. >> %2
echo exec (@cmdSQL) >> %2
echo GO >> %2
echo. >> %2
echo declare @cmdSQL nvarchar(max) >> %2
echo set @cmdSQL = '' >> %2
echo. >> %2
echo print convert(varchar(30), getdate(), 121) + ' ALTER FULLTEXT CATALOG ...' >> %2
echo. >> %2
echo select @cmdSQL = ' >> %2
echo                     ALTER FULLTEXT CATALOG ' + quotename(name) + ' REORGANIZE' >> %2
echo     from sys.fulltext_catalogs >> %2
echo. >> %2
echo exec (@cmdSQL) >> %2
@echo on
GOTO :EOF

:truncate_compress_logs
set /a maxlogsizekb=1024
set /a maxlogsize=%maxlogsizekb% * 1024
cd /d "%~dpn0_logs"
for /f %%i in ('dir /B *.old') do (call :compress_large_logs %%i %maxlogsize% %maxlogsizekb%)
forfiles /M *.7z /d -60 /c "cmd /c (del /f /q @file >nul 2<&1 & if exist @file (echo  - Error: File @file was not deleted.) else (echo  + OK! File @file was deleted.))" 2>nul
if not %ERRORLEVEL% EQU 0 echo  + OK! - Old files not found.
%~d0 & cd "%~dp0"
GOTO :EOF

:compress_large_logs
if %~z1 gtr %2 (
"%~dp07za.exe" a -t7z -mmt=2 -mx=9 -ssw -y "%1.%date_formatted%.7z" "%1"
echo  ---!!!--- %DATE% %TIME% File was greater than %3 KB. Compressed into %1.%date_formatted%.7z and truncated. > "%1"
)
GOTO :EOF

:create_old_log
@echo off
cd /d "%~dpn0_logs"
for %%g in (log sql cmd) do (
for /f %%i in ('dir /B *.%%g') do (
echo. >> %%i.old
echo [[%%i %DATE% %TIME% START]] >> %%i.old
echo. >> %%i.old
copy /B %%i.old + %%i %%i.old
echo. >> %%i.old
echo [[%%i %DATE% %TIME% START]] >> %%i.old
echo. >> %%i.old
))
GOTO :EOF

:create_full_log
@echo off
cd /d "%~dpn0_logs"
echo. > "%~dpn0_logs\%~n0_full_%date_formatted%.log"
echo "%~dpn0_logs\%~n0_full_%date_formatted%.log" %DATE% %TIME% __START__ >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
echo. >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
for %%g in (log sql cmd) do (
for /f %%i in ('dir /B *.%%g') do (
echo. >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
echo   [[%%i START]] >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
echo. >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
copy /B "%~dpn0_logs\%~n0_full_%date_formatted%.log" + "%%i" "%~dpn0_logs\%~n0_full_%date_formatted%.log"
echo. >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
echo   [[%%i END]] >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
echo. >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
))
echo "%~dpn0_logs\%~n0_full_%date_formatted%.log" %DATE% %TIME% __END__ >> "%~dpn0_logs\%~n0_full_%date_formatted%.log"
"%~dp07za.exe" a -t7z -mmt=2 -mx=9 -ssw -y "%~dpn0_logs\%~n0_full_%date_formatted%.log.7z" "%~dpn0_logs\%~n0_full_%date_formatted%.log"
del /f /q "%~dpn0_logs\%~n0_full_%date_formatted%.log"  >nul 2<&1

GOTO :EOF

:log_and_time
echo --- Started %* on %time%.
set log_and_time_title=%2
if defined log_and_time_title set log_and_time_title=[%log_and_time_title%]
title Running %1 %log_and_time_title%
set log_and_time_title=
call %*
echo --- Finished %* on %time%.
GOTO :EOF

:gen_date_formatted
@echo off
SETLOCAL ENABLEEXTENSIONS
if "%date%A" LSS "A" (set toks=1-3) else (set toks=2-4)
for /f "tokens=2-4 delims=(-)" %%a in ('echo:^|date') do (
	for /f "tokens=%toks% delims=.-/ " %%i in ('date/t') do (
		set 'dd'=%%i
		set 'mm'=%%j
		set 'yy'=%%k))
if %'yy'% LSS 100 set 'yy'=20%'yy'%
ENDLOCAL & SET date_formatted=%'yy'%_%'mm'%_%'dd'%
@echo on
GOTO :EOF

:echo_variable
call echo - Variable used: [%1] = [%%%1%%]
GOTO :EOF

:get_database_list
rem for /f %%o in ('%sqlcmd_string% -s "," -h -1 -W -Q "set nocount on; select name from [msdb].[sys].[databases] where database_id>4"') do call :gen_database_list %%o
for /f %%o in ('%sqlcmd_string% -s "," -h -1 -W -Q "set nocount on; with fs as (select database_id, type, size from sys.master_files f) select name from sys.databases d where d.database_id>4 order by (select sum(size) from fs where type = 0 and fs.database_id = d.database_id)"') do call :gen_database_list %%o
GOTO :EOF

:get_name_list
for /f %%i in ('dir /B /A:-D *_%year%_*.7z') do call :gen_name_list_prep %%i
if not defined name_list set /a exit_code=4 && echo Error: No suitable databases\files found!
GOTO :EOF

:uncompress_backups
if exist "%~dp07za.exe" (call :uncompress_backup_archives) else (set /a exit_code=2 && echo Error: 7za.exe not found.)
GOTO :EOF

:run_scripts
for %%f in (%name_list%) do call :run_script %%f
GOTO :EOF

:gen_scripts
for %%e in (%name_list%) do call :gen_restore_script %%e
GOTO :EOF

:check_required_utilities
@echo off
where sqlcmd>nul 2<&1
if %ERRORLEVEL% EQU 1 (
echo Utility SQLCMD not found!
set /a exit_code=6
@echo on && exit /B %exit_code%)
if not exist "%~dp07za.exe" (
echo Utility 7za.exe not found!
set /a exit_code=7
@echo on && exit /B %exit_code%)
@echo on
GOTO :EOF

:main
cd /d "%0\.."
chcp 1251 >nul 2<&1
echo. >nul 2<&1 
echo - %0 Started on %date% at %time%.

call :log_and_time :gen_date_formatted

if not defined year for /f %%a in ('wmic path win32_localtime get year /value ^| findstr ^= ') do (set %%a)
if not defined shrink_mode (set shrink_string=%shrink_percentage%) else (set shrink_string=%shrink_percentage%, %shrink_mode%)
for %%c in (name_list,long_name_list,database_list,exit_code,position_in_list) do set %%c=
for %%d in (year,sql_data_dir,sqlcmd_string,db_file_maxsize,db_file_flegrowth,check_restore_status_string,shrink_percentage,shrink_mode,hostname,shrink_string,date_formatted,cas_factor,is_unattended,db_reindex_exceptions) do call :echo_variable %%d

call :check_required_utilities
if defined exit_code exit /B %exit_code%
call :log_and_time :get_database_list && call :echo_variable database_list
call :log_and_time :get_name_list 
if defined exit_code (exit /B %exit_code%) else (call :echo_variable name_list && call :echo_variable long_name_list)
call :log_and_time :uncompress_backups
if defined exit_code (exit /B %exit_code%) else (call :echo_variable cas_disk_free_space && call :echo_variable cas_space_required)
call :log_and_time :gen_scripts
call :log_and_time :run_scripts
call :log_and_time :clean_garbage

echo - %0 Finished on %date% at %time%.
echo.