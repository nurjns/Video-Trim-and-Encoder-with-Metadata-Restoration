:: Version 2.4.3 - 01.09.2026 - @nurjns

@echo off
setlocal enabledelayedexpansion
title Batch Video Cutter und Encoder

where ffmpeg >nul 2>&1
if errorlevel 1 (
	echo [FEHLER] ffmpeg nicht gefunden^^! Bitte sicherstellen, dass ffmpeg im PATH ist.
	pause & exit /b 1
)
where ffprobe >nul 2>&1
if errorlevel 1 (
	echo [FEHLER] ffprobe nicht gefunden^^! Bitte sicherstellen, dass ffprobe im PATH ist.
	pause & exit /b 1
)
where exiftool >nul 2>&1
if errorlevel 1 (
	echo [FEHLER] ExifTool nicht gefunden^^! Bitte sicherstellen, dass ExifTool im PATH ist.
	pause & exit /b 1
)

:: Benutzerabfrage: Codec-Auswahl
echo Waehle Codec:
echo 1 - H.265 - Gute Kompression, breite Unterstuetzung (Standard)
echo 2 - AV1 - Beste Kompression, Geschwindigkeit haengt von Qualitaetsstufe ab, fuer neuere Geraete
set /p CODECWAHL="Eingabe (1 oder 2): "

if not "%CODECWAHL%"=="1" if not "%CODECWAHL%"=="2" (
	echo Ungueltige Eingabe. Standard: H.265 wird verwendet.
	set CODECWAHL=1
)

:: Benutzerabfrage: Start-Sekunden schneiden
:ASK_CUT_START
set CUT_START=
set /p CUT_START="Wie viele Sekunden vom ANFANG sollen entfernt werden? "
if "%CUT_START%"=="" set CUT_START=0
if not "%CUT_START%"=="0" (
	echo %CUT_START%| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 (
		echo Ungueltige Eingabe bei Startzeit^^!
		goto ASK_CUT_START
	)
)

:: Benutzerabfrage: End-Sekunden schneiden
:ASK_CUT_END
set CUT_END=
set /p CUT_END="Wie viele Sekunden vom ENDE sollen entfernt werden? "
if "%CUT_END%"=="" set CUT_END=0
if not "%CUT_END%"=="0" (
	echo %CUT_END%| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 (
		echo Ungueltige Eingabe bei Endzeit^^!
		goto ASK_CUT_END
	)
)

:: Benutzerabfrage: CRF-Wert
:ASK_CRF 
set CRF_WERT=
if "%CODECWAHL%"=="1" ( 
	echo H.265 CRF-Wert ^(18=hoch, 24=normal, 30=niedrig, 35=sehr niedrig^) - Leer lassen = nur schneiden 
) else (
	echo AV1 CRF-Wert ^(18=sehr hoch, 22=hoch, 30=normal, 40=niedrig, 50=sehr niedrig^) - Leer lassen = nur schneiden 
) 
set /p CRF_WERT="Welcher CRF-Wert soll verwendet werden? "
 
if not "%CRF_WERT%"=="" (
	echo %CRF_WERT%| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 goto :CRF_FEHLER
	if %CRF_WERT% LSS 16 goto :CRF_FEHLER
	if %CRF_WERT% GTR 50 goto :CRF_FEHLER
)
goto :CRF_OK
:CRF_FEHLER
echo Ungueltige Eingabe bei CRF-Wert^^!
goto ASK_CRF
:CRF_OK

:: Benutzerabfrage: Zeitzone
:: Automatisch Sommer-/Winterzeit erkennen für Deutschland
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time'); $now = Get-Date; if($tz.IsDaylightSavingTime($now)) {'+02:00'} else {'+01:00'}"`) do set "SYSTEM_TZ=%%i"

set /p "TIMEZONE_NECESSARY=Muss Zeitzone in Datei geschrieben werden? Notwendig bei Videos ohne GPS-Daten (y/n): "
if /i "!TIMEZONE_NECESSARY!"=="y" (
	set /p "TIMEZONE=Zeitzone fuer Metadaten (Format: +/-XX:00, leer fuer Standard: !SYSTEM_TZ!): "
	if "!TIMEZONE!"=="" (
		echo Leere Eingabe. Standard: !SYSTEM_TZ! wird verwendet
		set "TIMEZONE=!SYSTEM_TZ!"
	)
) else (
	set "TIMEZONE="
)

:: Benutzerabfrage: Welches Datum als Aufnahmedatum verwenden?
echo Welches Datum soll als Aufnahmedatum verwendet werden? Bei Videos von DJI und DJI Mimo wird automatisch das Datum aus dem Dateinamen verwendet. Bei Videos mit GPS-Daten aber angegebener Zeitzone wird Auswahl 1 empfohlen.
echo 1 - Aenderungsdatum der Datei (Standard)
echo 2 - Aufnahmedatum aus Metadaten
set /p DATETOUSE="Eingabe (1 oder 2): "

if not "%DATETOUSE%"=="1" if not "%DATETOUSE%"=="2" (
	echo Ungueltige Eingabe. Standard: "Aenderungsdatei der Datei" wird verwendet
	set DATETOUSE=1
)

:: Benutzerabfrage: Audio entfernen?
set /p REMOVE_AUDIO="Ton entfernen? (y/n): "
if /i "%REMOVE_AUDIO%"=="y" (
	set "AUDIO_PARAM=-an"
	echo Audio wird entfernt
) else (
	set "AUDIO_PARAM=-c:a aac -b:a 160k"
)

:: Schleife durch alle MP4-Dateien
for %%F in (*.mp4) do (
	:: Prüfen ob bereits verarbeitetes Video (enthält _crf, _cut oder _AV1)
	set "IS_PROCESSED=0"
	echo %%F | findstr /i "_crf" >nul && set "IS_PROCESSED=1"
	echo %%F | findstr /i "_cut" >nul && set "IS_PROCESSED=1"
	echo %%F | findstr /i "_AV1" >nul && set "IS_PROCESSED=1"

	if !IS_PROCESSED! == 1 (
		echo [OK] Ignoriert: %%F - bereits verarbeitetes Video
	) else (
		:: Prüfen ob die Datei ein gültiges Video ist
		ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "%%F" >nul 2>&1
		if !errorlevel! NEQ 0 (
			echo [FEHLER] Ignoriert: %%F - ungueltige oder beschaedigte Videodatei
		) else (
			:: Prüfen ob bereits ein gerendertes Video mit EXAKT den gleichen Einstellungen existiert
			set "BASENAME=%%~nF"
			set "RENDERED_EXISTS=0"

			:: Prüfen ob ein Video ohne CRF (nur _cut) existiert und aktuell auch ohne CRF verarbeitet werden soll
			if "%CRF_WERT%"=="" (
				if exist "!BASENAME!_cut.mp4" set "RENDERED_EXISTS=1"
			) else (
				:: CRF-Wert ist gesetzt - prüfen auf exakte Übereinstimmung
				if "%CODECWAHL%"=="1" (
					:: H.265 - prüfen auf exakte CRF-Übereinstimmung
					if exist "!BASENAME!_crf!CRF_WERT!.mp4" set "RENDERED_EXISTS=1"
				) else (
					:: AV1 - prüfen auf exakte CRF-Übereinstimmung
					if exist "!BASENAME!_AV1_crf!CRF_WERT!.mp4" set "RENDERED_EXISTS=1"
				)
			)

			if !RENDERED_EXISTS! == 1 (
				echo [OK] Ignoriert: %%F - bereits mit gleichen Einstellungen gerendert
			) else (
				echo Bearbeite: %%F

				:: Prüfen ob DJI Action Video, falls ja, Datum aus Dateinamen verwenden
				echo %%~nF | findstr /r /i "^DJI_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_" >nul
				if !errorlevel! == 0 (
					:: Dateiname ohne Extension
					set "FNAME=%%~nF"
					:: 14-stellige Zeitkette nach "DJI_"
					for /f "tokens=2 delims=_" %%A in ("!FNAME!") do (
						set "DATETIME=%%A"
					)
					set "YYYY=!DATETIME:~0,4!"
					set "MM=!DATETIME:~4,2!"
					set "DD=!DATETIME:~6,2!"
					set "hh=!DATETIME:~8,2!"
					set "nn=!DATETIME:~10,2!"
					set "ss=!DATETIME:~12,2!"
					:: Aufnahmedatum mit Offset festlegen
					set "TIMESTAMP=!YYYY!:!MM!:!DD! !hh!:!nn!:!ss!"
					echo [INFO] DJI Action Video erkannt, verwende Aufnahmedatum aus Dateinamen...

				) else (
					:: Prüfen ob DJI Mimo Datei, falls ja, Datum aus Dateinamen verwenden
					echo %%~nF | findstr /b /i "dji_mimo_" >nul
					if !errorlevel! == 0 (
						:: Dateiname ohne Extension
						set "FNAME=%%~nF"
						:: tokens=3,4: überspringe "dji_mimo"
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
						:: Aufnahmedatum mit Offset festlegen
						set "TIMESTAMP=!YYYY!:!MM!:!DD! !hh!:!nn!:!ss!"
						echo [INFO] DJI Mimo Datei erkannt, verwende Aufnahmedatum aus Dateinamen...
					) else (
						:: Datum entsprechend der Benutzerwahl auslesen
						if "!DATETOUSE!"=="2" (
							:: Aufnahmedatum aus Video-Metadaten (Create Date) verwenden, sofern vorhanden
							for /f "usebackq delims=" %%T in (`exiftool.exe -s3 -CreateDate "%%F"`) do (
								set "TIMESTAMP=%%T"
							)
							if "!TIMESTAMP!"=="0000:00:00 00:00:00" set "TIMESTAMP="
							if not defined TIMESTAMP (
								echo Warnung: Kein Aufnahmedatum gefunden fuer %%F, verwende Aenderungsdatum
								for /f "usebackq delims=" %%T in (`powershell -NoLogo -NoProfile -Command "(Get-Item '%%F').LastWriteTime.ToString('yyyy:MM:dd HH:mm:ss')"`) do (
									set "TIMESTAMP=%%T"
								)
							)
						) else (
							:: Änderungsdatum der Datei (Standard)
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
								if !CRF_WERT! LEQ 22 (
									set "PRESET=2"
								) else if !CRF_WERT! LEQ 28 (
									set "PRESET=3"
								) else if !CRF_WERT! LEQ 35 (
									set "PRESET=6"
								) else (
									set "PRESET=10"
								)
								set "OUTFILE=!OUTFILE!_AV1_crf!CRF_WERT!.mp4"
								ffmpeg -y -ss !CUT_START! -i "%%F" -t !REMAINING! -c:v libsvtav1 -crf !CRF_WERT! -preset !PRESET! -pix_fmt yuv420p -movflags +faststart !AUDIO_PARAM! "!OUTFILE!"
							)
						)

						:: ExifTool: UTC in MP4/QuickTime-Felder, lokale Zeit + Offset in EXIF
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

						echo [OK] Verarbeitet: !OUTFILE!
					) else (
						echo [OK] Uebersprungen: %%F - nur !REMAINING!s wuerden uebrig bleiben
					)
				) else (
					echo [OK] Uebersprungen: %%F - !VIDEO_PLUS_3! nicht > !CUTS_TOTAL!
				)
			)
		)
	)
)

echo.
powershell -c [console]::beep(500,200)
echo Alle Videos wurden verarbeitet.
pause
