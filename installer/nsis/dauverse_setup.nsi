; DAUVERSE REMOTE DESKTOP V1.0 — NSIS Windows Installer & Clean Uninstaller
; Respects Sections 07, 18 & 24:
; - Selects E:\Program Files ONLY when E:\ is a real fixed local disk (GetDriveTypeW == DRIVE_FIXED = 3).
; - Creates rollback backup synchronized with scripts\windows\rollback_windows_release.ps1.
; - Windows Service registration is OPTIONAL (/o unchecked by default — never auto-installs without Boss consent)
;   and uses SCM name "RustDesk" matching upstream src/platform/windows.rs is_self_service_running().
; - Never modifies Windows Defender, Firewall exclusions, Secure Boot, or DSE.

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

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

Var HasFixedDriveE

Function .onInit
  StrCpy $HasFixedDriveE "0"
  ; DRIVE_FIXED == 3 (prevents installing onto USB sticks, DVDs, or network shares mounted at E:)
  System::Call 'kernel32::GetDriveTypeW(w "E:\") i .r0'
  ${If} $0 == 3
    StrCpy $HasFixedDriveE "1"
    StrCpy $INSTDIR "E:\Program Files\DAUVERSE Remote Desktop"
  ${EndIf}
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

  ; Gracefully stop optional service & running app before upgrade
  nsExec::ExecToLog 'sc.exe stop RustDesk'
  nsExec::ExecToLog 'taskkill.exe /IM DAUVERSE_REMOTE.exe /F'

  ; Create Rollback Snapshot if upgrading an existing installation (matches rollback_windows_release.ps1)
  IfFileExists "$INSTDIR\DAUVERSE_REMOTE.exe" 0 SkipBackup
    CreateDirectory "$INSTDIR.rollback_backup"
    CopyFiles /SILENT "$INSTDIR\*.*" "$INSTDIR.rollback_backup"
    ${If} $HasFixedDriveE == "1"
      CreateDirectory "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release"
      CopyFiles /SILENT "$INSTDIR\*.*" "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release"
    ${EndIf}
  SkipBackup:

  SetOutPath "$INSTDIR"
  File /r "${STAGING_DIR}\*.*"

  CreateDirectory "$SMPROGRAMS\DAUVERSE Remote Desktop"
  CreateShortcut "$SMPROGRAMS\DAUVERSE Remote Desktop\DAUVERSE Remote Desktop.lnk" "$INSTDIR\DAUVERSE_REMOTE.exe"
  CreateShortcut "$DESKTOP\DAUVERSE Remote Desktop.lnk" "$INSTDIR\DAUVERSE_REMOTE.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "DisplayName" "DAUVERSE REMOTE DESKTOP V1.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "DisplayVersion" "1.0.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "Publisher" "DAUVERSE Ecosystem (AGPL-3.0)"
SectionEnd

Section /o "Register Windows Startup Service (Optional — Unchecked Until Boss Approves)" SecService
  nsExec::ExecToLog 'sc.exe create RustDesk binPath= "\"$INSTDIR\rustdesk.exe\" --service" start= auto DisplayName= "DAUVERSE Remote Desktop Service (RustDesk Engine)"'
  nsExec::ExecToLog 'sc.exe failure RustDesk reset= 86400 actions= restart/5000/restart/15000/restart/30000'
  nsExec::ExecToLog 'sc.exe start RustDesk'
SectionEnd

Section "Uninstall"
  nsExec::ExecToLog 'sc.exe stop RustDesk'
  nsExec::ExecToLog 'sc.exe delete RustDesk'
  nsExec::ExecToLog 'taskkill.exe /IM DAUVERSE_REMOTE.exe /F'

  Delete "$DESKTOP\DAUVERSE Remote Desktop.lnk"
  RMDir /r "$SMPROGRAMS\DAUVERSE Remote Desktop"
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop"
SectionEnd
