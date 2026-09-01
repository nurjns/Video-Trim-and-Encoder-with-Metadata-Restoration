:: Version 2.4.4 - 2026-09-01 - @nurjns

@echo off
setlocal enabledelayedexpansion
title Batch Video Cutter and Encoder

where ffmpeg >nul 2>&1
if errorlevel 1 (
	echo [ERROR] ffmpeg not found^^! Please ensure ffmpeg is in your PATH.
	pause & exit /b 1
)
where ffprobe >nul 2>&1
if errorlevel 1 (
	echo [ERROR] ffprobe not found^^! Please ensure ffprobe is in your PATH.
	pause & exit /b 1
)
where exiftool >nul 2>&1
if errorlevel 1 (
	echo [ERROR] ExifTool not found^^! Please ensure ExifTool is in your PATH.
	pause & exit /b 1
)

:: User prompt: Codec selection
echo Select Codec:
echo 1 - H.265 - Good compression, broad support (Default)
echo 2 - AV1 - Best compression, speed depends on quality setting, for newer devices
set /p CODECWAHL="Input (1 or 2): "

if not "%CODECWAHL%"=="1" if not "%CODECWAHL%"=="2" (
	echo Invalid input. Defaulting to H.265.
	set CODECWAHL=1
)

:: User prompt: Cut start seconds
:ASK_CUT_START
set CUT_START=
set /p CUT_START="How many seconds should be removed from the BEGINNING? "
if "%CUT_START%"=="" set CUT_START=0
if not "%CUT_START%"=="0" (
	echo %CUT_START%| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 (
		echo Invalid input for start time^^!
		goto ASK_CUT_START
	)
)

:: User prompt: Cut end seconds
:ASK_CUT_END
set CUT_END=
set /p CUT_END="How many seconds should be removed from the END? "
if "%CUT_END%"=="" set CUT_END=0
if not "%CUT_END%"=="0" (
	echo %CUT_END%| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 (
		echo Invalid input for end time^^!
		goto ASK_CUT_END
	)
)

:: User prompt: CRF value
:ASK_CRF 
set CRF_WERT=
if "%CODECWAHL%"=="1" ( 
	echo H.265 CRF value ^(18=high, 24=normal, 30=low, 35=very low^) - Leave empty = cut only 
) else (
	echo AV1 CRF value ^(18=very high, 22=high, 30=normal, 40=low, 50=very low^) - Leave empty = cut only 
) 
set /p CRF_WERT="Which CRF value should be used? "
 
if not "%CRF_WERT%"=="" (
	echo %CRF_WERT%| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 goto :CRF_FEHLER
	if %CRF_WERT% LSS 16 goto :CRF_FEHLER
	if %CRF_WERT% GTR 50 goto :CRF_FEHLER
)
goto :CRF_OK
:CRF_FEHLER
echo Invalid input for CRF value^^!
goto ASK_CRF
:CRF_OK

set "PRESET_MANUAL="
if not "%CODECWAHL%"=="2" goto :PRESET_DONE

:ASK_PRESET
set "PRESET_MANUAL="
set /p PRESET_MANUAL="AV1 preset (0-13, 0=slow/small, 13=fast/large, leave empty = automatic): "
if not "%PRESET_MANUAL%"=="" (
	echo %PRESET_MANUAL%| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 goto :PRESET_FEHLER
	if %PRESET_MANUAL% GTR 13 goto :PRESET_FEHLER
)
goto :PRESET_DONE
:PRESET_FEHLER
echo Invalid preset value^^!
goto ASK_PRESET

:PRESET_DONE

:: User prompt: Timezone
:: Automatically detect daylight saving time for Germany
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time'); $now = Get-Date; if($tz.IsDaylightSavingTime($now)) {'+02:00'} else {'+01:00'}"`) do set "SYSTEM_TZ=%%i"

set /p "TIMEZONE_NECESSARY=Write timezone to file? Required for videos without GPS data (y/n): "
if /i "!TIMEZONE_NECESSARY!"=="y" (
	set /p "TIMEZONE=Timezone for metadata (Format: +/-XX:00, empty for default: !SYSTEM_TZ!): "
	if "!TIMEZONE!"=="" (
		echo Empty input. Defaulting to !SYSTEM_TZ!
		set "TIMEZONE=!SYSTEM_TZ!"
	)
) else (
	set "TIMEZONE="
)

:: User prompt: Which date to use as recording date?
echo Which date should be used as the recording date? For videos from DJI and DJI Mimo, the date from the filename is used automatically. For videos with GPS data but specified timezone, Option 1 is recommended.
echo 1 - File modification date (Default)
echo 2 - Recording date from metadata
set /p DATETOUSE="Input (1 or 2): "

if not "%DATETOUSE%"=="1" if not "%DATETOUSE%"=="2" (
	echo Invalid input. Defaulting to "File modification date".
	set DATETOUSE=1
)

:: User prompt: Remove audio?
set /p REMOVE_AUDIO="Remove audio? (y/n): "
if /i "%REMOVE_AUDIO%"=="y" (
	set "AUDIO_PARAM=-an"
	echo Audio will be removed
) else (
	set "AUDIO_PARAM=-c:a aac -b:a 160k"
)

:: Loop through all MP4 files
for %%F in (*.mp4) do (
	:: Check if video was already processed (contains _crf, _cut, or _AV1)
	set "IS_PROCESSED=0"
	echo %%F | findstr /i "_crf" >nul && set "IS_PROCESSED=1"
	echo %%F | findstr /i "_cut" >nul && set "IS_PROCESSED=1"
	echo %%F | findstr /i "_AV1" >nul && set "IS_PROCESSED=1"

	if !IS_PROCESSED! == 1 (
		echo [OK] Ignored: %%F - already processed video
	) else (
		:: Check if file is a valid video
		ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "%%F" >nul 2>&1
		if !errorlevel! NEQ 0 (
			echo [ERROR] Ignored: %%F - invalid or corrupted video file
		) else (
			:: Check if a rendered video with EXACTLY the same settings already exists
			set "BASENAME=%%~nF"
			set "RENDERED_EXISTS=0"

			:: Check if a video without CRF (cut only) exists and is currently set to be processed without CRF
			if "%CRF_WERT%"=="" (
				if exist "!BASENAME!_cut.mp4" set "RENDERED_EXISTS=1"
			) else (
				:: CRF value is set - check for exact match
				if "%CODECWAHL%"=="1" (
					:: H.265 - check for exact CRF match
					if exist "!BASENAME!_crf!CRF_WERT!.mp4" set "RENDERED_EXISTS=1"
				) else (
					:: AV1 - check for exact CRF match
					if exist "!BASENAME!_AV1_crf!CRF_WERT!.mp4" set "RENDERED_EXISTS=1"
				)
			)

			if !RENDERED_EXISTS! == 1 (
				echo [OK] Ignored: %%F - already rendered with same settings
			) else (
				echo Processing: %%F

				:: Check if DJI Action video, if so, use date from filename
				echo %%~nF | findstr /r /i "^DJI_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_" >nul
				if !errorlevel! == 0 (
					:: Filename without extension
					set "FNAME=%%~nF"
					:: 14-digit timestamp string after "DJI_"
					for /f "tokens=2 delims=_" %%A in ("!FNAME!") do (
						set "DATETIME=%%A"
					)
					set "YYYY=!DATETIME:~0,4!"
					set "MM=!DATETIME:~4,2!"
					set "DD=!DATETIME:~6,2!"
					set "hh=!DATETIME:~8,2!"
					set "nn=!DATETIME:~10,2!"
					set "ss=!DATETIME:~12,2!"
					:: Set recording date with offset
					set "TIMESTAMP=!YYYY!:!MM!:!DD! !hh!:!nn!:!ss!"
					echo [INFO] DJI Action video detected, using recording date from filename...

				) else (
					:: Check if DJI Mimo file, if so, use date from filename
					echo %%~nF | findstr /b /i "dji_mimo_" >nul
					if !errorlevel! == 0 (
						:: Filename without extension
						set "FNAME=%%~nF"
						:: tokens=3,4: skip "dji_mimo"
						for /f "tokens=3,4 delims=_" %%A in ("!FNAME!") do (
							set "FILEDATE=%%A"
							set "FILETIME=%%B"
						)
						set "YYYY=!FILEDATE:~0,4!"
						set "MM=!FILEDATE:~4,2!"
						set "DD=!FILEDATE:~6,2!"
						set "hh=!FILETIME:~0,2!"
						set "nn=!FILETIME:~2,2!"
						set "ss=!FILETIME:~4,2!"
						:: Set recording date with offset
						set "TIMESTAMP=!YYYY!:!MM!:!DD! !hh!:!nn!:!ss!"
						echo [INFO] DJI Mimo file detected, using recording date from filename...
					) else (
						:: Read date according to user selection
						if "!DATETOUSE!"=="2" (
							:: Use recording date from video metadata (Create Date) if present
							for /f "usebackq delims=" %%T in (`exiftool.exe -s3 -CreateDate "%%F"`) do (
								set "TIMESTAMP=%%T"
							)
							if "!TIMESTAMP!"=="0000:00:00 00:00:00" set "TIMESTAMP="
							if not defined TIMESTAMP (
								echo Warning: No recording date found for %%F, using modification date
								for /f "usebackq delims=" %%T in (`powershell -NoLogo -NoProfile -Command "(Get-Item '%%F').LastWriteTime.ToString('yyyy:MM:dd HH:mm:ss')"`) do (
									set "TIMESTAMP=%%T"
								)
							)
						) else (
							:: File modification date (Default)
							for /f "usebackq delims=" %%T in (`powershell -NoLogo -NoProfile -Command "(Get-Item '%%F').LastWriteTime.ToString('yyyy:MM:dd HH:mm:ss')"`) do (
								set "TIMESTAMP=%%T"
							)
						)
					)
				)

				for /f "usebackq delims=" %%D in (`ffprobe -v error -select_streams v:0 -show_entries format^=duration -of default^=nokey^=1:noprint_wrappers^=1 "%%F"`) do (
					set "DURATION=%%D"
				)
				for /f "tokens=1 delims=." %%T in ("!DURATION!") do set /a INTDURATION=%%T
				set /a CUTS_TOTAL=!CUT_START!+!CUT_END!
				set /a VIDEO_PLUS_3=!INTDURATION!+3
				if !VIDEO_PLUS_3! GTR !CUTS_TOTAL! (
					set /a REMAINING=!INTDURATION!-!CUTS_TOTAL!
					if !REMAINING! GEQ 1 (
						set "OUTFILE=%%~nF"
						if "%CRF_WERT%"=="" (
							set "OUTFILE=!OUTFILE!_cut.mp4"
							if /i "%REMOVE_AUDIO%"=="y" (
								ffmpeg -y -i "%%F" -ss !CUT_START! -t !REMAINING! -c:v copy -an "!OUTFILE!"
							) else (
								ffmpeg -y -i "%%F" -ss !CUT_START! -t !REMAINING! -c copy "!OUTFILE!"
							)
						) else (
							if "%CODECWAHL%"=="1" (
								:: H.265
								set "OUTFILE=!OUTFILE!_crf!CRF_WERT!.mp4"
								ffmpeg -y -ss !CUT_START! -i "%%F" -t !REMAINING! -c:v libx265 -crf !CRF_WERT! -preset medium -pix_fmt yuv420p -tag:v hvc1 -movflags +faststart !AUDIO_PARAM! "!OUTFILE!"
							) else (
								:: AV1
								if not "%PRESET_MANUAL%"=="" (
									set "PRESET=%PRESET_MANUAL%"
								) else (
									if !CRF_WERT! LEQ 22 (
										set "PRESET=2"
									) else if !CRF_WERT! LEQ 28 (
										set "PRESET=3"
									) else if !CRF_WERT! LEQ 35 (
										set "PRESET=6"
									) else (
										set "PRESET=10"
									)
								)
								set "OUTFILE=!OUTFILE!_AV1_crf!CRF_WERT!.mp4"
								ffmpeg -y -ss !CUT_START! -i "%%F" -t !REMAINING! -c:v libsvtav1 -crf !CRF_WERT! -preset !PRESET! -pix_fmt yuv420p -movflags +faststart !AUDIO_PARAM! "!OUTFILE!"
							)
						)

						:: ExifTool: UTC in MP4/QuickTime fields, local time + offset in EXIF
						if defined TIMEZONE (
							exiftool.exe -overwrite_original ^
								"-DateTimeOriginal=!TIMESTAMP!!TIMEZONE!" ^
								"-OffsetTimeOriginal=!TIMEZONE!" ^
								"-QuickTime:CreateDate=!TIMESTAMP!" ^
								"-QuickTime:ModifyDate=!TIMESTAMP!" ^
								"-QuickTime:TrackCreateDate=!TIMESTAMP!" ^
								"-QuickTime:TrackModifyDate=!TIMESTAMP!" ^
								"-QuickTime:MediaCreateDate=!TIMESTAMP!" ^
								"-QuickTime:MediaModifyDate=!TIMESTAMP!" ^
								"-FileModifyDate=!TIMESTAMP!" ^
								"!OUTFILE!"
						) else (
							exiftool.exe -overwrite_original -P -TagsFromFile "%%F" ^
								"-DateTimeOriginal" ^
								"-CreateDate" ^
								"-ModifyDate" ^
								"-FileModifyDate" ^
								"-OffsetTimeOriginal" ^
								"-OffsetTime" ^
								"-OffsetTimeDigitized" ^
								"!OUTFILE!"
						)

						echo [OK] Processed: !OUTFILE!
					) else (
						echo [OK] Skipped: %%F - only !REMAINING!s would remain
					)
				) else (
					echo [OK] Skipped: %%F - !VIDEO_PLUS_3! not > !CUTS_TOTAL!
				)
			)
		)
	)
)

echo.
powershell -c [console]::beep(500,200)
echo All videos have been processed.
pause
