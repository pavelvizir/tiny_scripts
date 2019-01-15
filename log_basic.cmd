@echo off
title PLEASE_WAIT... & prompt .
if "%1"=="log" goto :main
if exist "%~dpn0.log" type "%~dpn0.log" >> "%~dpn0.old"
if exist "%~dpn0.log" del /f /q "%~dpn0.log" >nul 2<&1
call "%~f0" log >>"%~dpn0.log" 2<&1
if exist "%~dpn0_clean.log" type "%~dpn0_clean.log" >> "%~dpn0_clean.old"
if exist "%~dpn0_clean.old" echo. >> "%~dpn0_clean.old"
if exist "%~dpn0_clean.log" del /f /q "%~dpn0_clean.log"
for /f "delims=¹" %%G in ('type "%~dpn0.log" ^| findstr /v "^\..*"') do echo %%G >> "%~dpn0_clean.log"
if not exist "%~dpn0_logs" mkdir "%~dpn0_logs"
call :create_old_log
call :truncate_compress_logs
robocopy /MOV "%~dp0\" "%~dpn0_logs\\" *.old
robocopy /MOV "%~dp0\" "%~dpn0_logs\\" *.log
robocopy "%~dp0\" "%~dpn0_logs\\" %~nx0
call :create_full_log
exit /B

:truncate_compress_logs
set /a maxlogsizekb=1024
set /a maxlogsize=%maxlogsizekb% * 1024
cd /d "%~dpn0_logs"
for /f %%i in ('dir /B *.old') do (call :compress_large_logs %%i %maxlogsize% %maxlogsizekb%)
forfiles /M *.7z /d -60 /c "cmd /c (del /f /q @file >nul 2<&1 & if exist @file (echo  - Error: File @file was not deleted.) else (echo  + OK! File @file was deleted.))" 2>nul
if not %ERRORLEVEL% EQU 0 echo  + OK! - Old files not found.
cd /d "%0\.."
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
del /f /q "%~dpn0_logs\%~n0_full_%date_formatted%.log" >nul 2<&1
GOTO :EOF

:log_and_time
echo --- Started %* on %time%.
call %*
echo --- Finished %* on %time%.
GOTO :EOF

:tasks_export
set te_userid=
set te_name=
set te_strings=Author,UserId
set te_cp_list=1251,866
set te_fo_list=list,table
for /f "tokens=2 delims=:" %%i in ('chcp') do set /a te_current_cp=%%i
for /f %%i in ('hostname') do set te_current_hostname=%%i
if not exist "%~dpn0_tasks_export_dir" mkdir "%~dpn0_tasks_export_dir" >nul 2<&1
cd "%~dpn0_tasks_export_dir"
@echo off
for %%i in (%te_name%,%te_strings%) do (for %%a in (%te_cp_list%) do (for %%j in (%te_fo_list%) do if exist tasks_export_%te_current_hostname%_%%i_%%j_%%a.txt del /f /q tasks_export_%te_current_hostname%_%%i_%%j_%%a.txt))
for /f "delims=," %%i in ('schtasks /Query /FO csv ^| findstr -i %te_name%') do call :tasks_export_print %%i %te_name%
@echo on
rem for %%i in (%te_strings%) do call :tasks_export_by_xml_tag %%i
cd "%~f0\.."
if not exist "%~dp0sql_scripts_backup" mkdir "%~dp0sql_scripts_backup" >nul 2<&1
if exist "%~dp0%te_current_hostname%_tasks_export.7z" del /f /q "%~dp0%te_current_hostname%_tasks_export.7z" >nul 2<&1
echo   --COMPRESSING TASKS_EXPORT...
"%~dp07za.exe" a -t7z -mmt=2 -mx=9 -ssw -y "%~dp0%te_current_hostname%_tasks_export.7z" "%~dpn0_tasks_export_dir" >>"%~dp0%te_current_hostname%_tasks_export.log" 2<&1
if %ERRORLEVEL% EQU 0 (echo  + OK!) else (echo  - FAIL!)
if exist "%~dp0sql_scripts_backup" if exist "%~dp0%te_current_hostname%_tasks_export.7z" copy /Y "%~dp0%te_current_hostname%_tasks_export.7z" "%~dp0sql_scripts_backup" >nul 2<&1
del /f /q "%~dp0%te_current_hostname%_tasks_export.7z"
rmdir /s /q "%~dpn0_tasks_export_dir" >nul 2<&1
@echo on
GOTO :EOF

:tasks_export_by_xml_tag
set te_string=%1
for /f "tokens=2 delims=," %%i in ('schtasks /query /fo csv /v ^| findstr -i %te_userid:\=\\%') do (for /f "tokens=1,2 delims=>" %%e in ('schtasks /query /xml /tn %%i ^| findstr -i %te_string%') do (for /f %%p in ("%%e>%%f>") do if /I "%%p"=="<%te_string%>%te_userid%</%te_string%>" call :tasks_export_print %%i %1))
goto :EOF

:tasks_export_print
set te_job_name=%1
set te_job_name=%te_job_name:\=%
schtasks /QUERY /XML /TN %te_job_name% > task_export_%te_current_hostname%_%2_%te_job_name%_xml.xml
for %%i in (%te_cp_list%) do (chcp %%i >nul 2<&1
for %%a in (%te_fo_list%) do (if not exist tasks_export_%te_current_hostname%_%2_%%a_%%i.txt echo Example usage: schtasks /create /tn [[job_name]] /xml [[xml_path]] /ru [[user]] /rp [[pass]] >tasks_export_%te_current_hostname%_%2_%%a_%%i.txt
schtasks /query /tn %te_job_name% /v /fo %%a >>tasks_export_%te_current_hostname%_%2_%%a_%%i.txt 
))
chcp %te_current_cp% >nul 2<&1
goto :EOF

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

:delete_temp
@echo off
set _disk=
set _folder=
D:
for /f "delims=?" %%G in ('dir "%_disk%" /A:D /B') do (if exist "%_disk%\%%G\%_folder%" (cd "%_disk%\%%G\%_folder%"
for /f "delims=?" %%H in ('dir "%_disk%\%%G\%_folder%" /B ^| findstr /i ".*\.temp"') do if exist %%H (echo Deleting file [ %_disk%\%%G\%_folder%\%%H ] ...
del /f /q %%H >nul 2<&1
if exist %%H (echo  - Error: File was not deleted.) else (echo  + OK!)
)
)
) >>"%~dp0delete_temp.log" 2<&1
cd /d "%0\.."
@echo on
GOTO :EOF

:delete_older_than
cd /d "%bkp_dir_dst%"
if not "%CD%" == "%bkp_dir_dst%" (echo  - Error: Couldn't go into directory "%bkp_dir_dst%".) & GOTO :EOF
echo  Deleting files older than %days_to_keep_backups% days:
forfiles /M *.7z /d -%days_to_keep_backups% /c "cmd /c (del /f /q @file >nul 2<&1 & if exist @file (echo  - Error: File @file was not deleted.) else (echo  + OK! File @file was deleted.))" 2>nul
if not %ERRORLEVEL% EQU 0 echo  + OK! - Old files not found.
cd /d "%0\.."
call :check_available_storage "%bkp_dir_dst%"
@echo on
GOTO :EOF

:check_available_storage
for /f "tokens=3 delims=," %%a in ('wmic logicaldisk get freespace^,deviceid ^/format:csv ^| findstr %~d1') do set cas_bytes=%%a
set /a cas_gbytes_dirty=%cas_bytes:~0,-10%
if not defined cas_gbytes_dirty set /a cas_gbytes_dirty=1
set /a cas_gbytes=%cas_gbytes_dirty%*93/100
@echo off
if %cas_gbytes% LSS %space_required_for_backup% (set /a days_to_keep_backups=%days_to_keep_backups%-1
echo WARNING!!! WARNING!!! WARNING!!! [[ Not enough storage space. Variable [days_to_keep_backups] has been decreased to %days_to_keep_backups%. ]] WARNING!!! WARNING!!! WARNING!!!
if %days_to_keep_backups% LEQ 30 (echo Variable [days_to_keep_backups] reached the minimum possible value of %days_to_keep_backups%. Aborting.) & GOTO :EOF
call :delete_older_than)
GOTO :EOF

:echo_variable
call echo - Variable used: [%1] = [%%%1%%]
GOTO :EOF

:main
@echo on
cd /d "%0\.."
chcp 1251 >nul 2<&1
echo. >nul 2<&1 
echo - %0 Started on %date% at %time%.
echo - Variables used:
for %%d in (variables) do call :echo_variable %%d

call :log_and_time :gen_date_formatted
call :log_and_time :tasks_export

echo - %0 Finished on %date% at %time%.
echo.
@echo off
rem for /f "tokens=3 delims=," %a in ('wmic logicaldisk get freespace^,deviceid ^/format:csv ^| findstr D:') do set a=%a 1.073 0.93
rem for %%c in (a,b,c,d) do set %%c=