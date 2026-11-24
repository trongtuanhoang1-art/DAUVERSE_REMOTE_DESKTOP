; DAUVERSE REMOTE DESKTOP V1.0 — NSIS Windows Installer & Clean Uninstaller
; Respects Section 07 & 18: Defaults to E:\Program Files when E:\ exists, creates rollback backup,
; optional Windows Service registration with failure recovery, never modifies Defender/AV.

!include "MUI2.nsh"
!include "FileFunc.nsh"

!ifndef OUT_FILE
  !define OUT_FILE "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe"
!endif
!ifndef STAGING_DIR
  !define STAGING_DIR "..\..\flutter\build\windows\x64\runner\Release"
!endif

Name "DAUVERSE REMOTE DESKTOP V1.0"
OutFile "${OUT_FILE}"
Unicode True
RequestExecutionLevel admin
InstallDir "$PROGRAMFILES64\DAUVERSE Remote Desktop"

Function .onInit
  IfFileExists "E:\*.*" 0 +2
    StrCpy $INSTDIR "E:\Program Files\DAUVERSE Remote Desktop"
FunctionEnd

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Vietnamese"
!insertmacro MUI_LANGUAGE "English"

Section "DAUVERSE Remote Core & Executive UI (Required)" SecCore
  SectionIn RO

  ; Create Rollback Snapshot if upgrading an existing installation
  IfFileExists "$INSTDIR\DAUVERSE_REMOTE.exe" 0 SkipBackup
    CreateDirectory "$INSTDIR\..\DAUVERSE_ROLLBACK_BACKUP"
    CopyFiles /SILENT "$INSTDIR\*.*" "$INSTDIR\..\DAUVERSE_ROLLBACK_BACKUP"
  SkipBackup:

  SetOutPath "$INSTDIR"
  File /r "${STAGING_DIR}\*.*"

  CreateDirectory "$SMPROGRAMS\DAUVERSE Remote Desktop"
  CreateShortcut "$SMPROGRAMS\DAUVERSE Remote Desktop\DAUVERSE Remote Desktop.lnk" "$INSTDIR\DAUVERSE_REMOTE.exe"
  CreateShortcut "$DESKTOP\DAUVERSE Remote Desktop.lnk" "$INSTDIR\DAUVERSE_REMOTE.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "DisplayName" "DAUVERSE REMOTE DESKTOP V1.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "DisplayVersion" "1.0.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "Publisher" "DAUVERSE Ecosystem (AGPL-3.0)"
SectionEnd

Section /o "Register Windows Startup Service (Optional — Requires Owner Consent)" SecService
  nsExec::ExecToLog 'sc.exe create DauverseRemoteService binPath= "\"$INSTDIR\rustdesk.exe\" --service" start= auto DisplayName= "DAUVERSE Remote Desktop Service"'
  nsExec::ExecToLog 'sc.exe failure DauverseRemoteService reset= 86400 actions= restart/5000/restart/15000/restart/30000'
  nsExec::ExecToLog 'sc.exe start DauverseRemoteService'
SectionEnd

Section "Uninstall"
  nsExec::ExecToLog 'sc.exe stop DauverseRemoteService'
  nsExec::ExecToLog 'sc.exe delete DauverseRemoteService'

  Delete "$DESKTOP\DAUVERSE Remote Desktop.lnk"
  RMDir /r "$SMPROGRAMS\DAUVERSE Remote Desktop"
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop"
SectionEnd
