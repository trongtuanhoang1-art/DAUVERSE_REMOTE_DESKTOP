; DAUVERSE REMOTE DESKTOP V1.0 — NSIS Windows Installer & Clean Uninstaller (RC2 Hardened)
; Remediates Codex Findings F03 & F11 while preserving Sections 07, 18 & 24:
; - Selects E:\Program Files ONLY when E:\ is a real fixed local disk (GetDriveTypeW == DRIVE_FIXED = 3).
; - Verifies Windows Service ("RustDesk") ImagePath ownership before stopping, modifying, or deleting:
;   external/pre-existing RustDesk installations and processes outside $INSTDIR are preserved untouched.
; - Scopes process termination strictly to executables residing under $INSTDIR\ via dauverse_setup_helper.ps1.
; - Generates SHA-256-manifested rollback backup (BACKUP_SHA256_MANIFEST.txt) synchronized with
;   scripts\windows\rollback_windows_release.ps1 before modifying an existing installation.
; - Windows Service registration remains OPTIONAL (/o unchecked by default) and refuses collision with
;   any external RustDesk service.
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
Var ServiceOwnedState ; "ABSENT", "OWNED", or "EXTERNAL"

!macro CHECK_RUSTDESK_SERVICE_OWNERSHIP RESULT_VAR TARGET_DIR
  ReadRegStr $R0 HKLM "SYSTEM\CurrentControlSet\Services\RustDesk" "ImagePath"
  ${If} $R0 == ""
    StrCpy ${RESULT_VAR} "ABSENT"
  ${Else}
    StrCpy $R1 $R0 1
    ${If} $R1 == '"'
      StrCpy $R0 $R0 "" 1
    ${EndIf}
    StrLen $R2 "${TARGET_DIR}\"
    StrCpy $R3 $R0 $R2
    ${If} $R3 == "${TARGET_DIR}\"
      StrCpy ${RESULT_VAR} "OWNED"
    ${Else}
      StrCpy ${RESULT_VAR} "EXTERNAL"
    ${EndIf}
  ${EndIf}
!macroend

Function .onInit
  SetRegView 64
  StrCpy $HasFixedDriveE "0"
  ; DRIVE_FIXED == 3 (prevents installing onto USB sticks, DVDs, or network shares mounted at E:)
  System::Call 'kernel32::GetDriveTypeW(w "E:\") i .r0'
  ${If} $0 == 3
    StrCpy $HasFixedDriveE "1"
    StrCpy $INSTDIR "E:\Program Files\DAUVERSE Remote Desktop"
  ${EndIf}
FunctionEnd

Function un.onInit
  SetRegView 64
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

  InitPluginsDir
  File "/oname=$PLUGINSDIR\dauverse_setup_helper.ps1" "${__FILEDIR__}\dauverse_setup_helper.ps1"

  ; F03: Check service ownership BEFORE stopping — never disrupt an external RustDesk installation
  !insertmacro CHECK_RUSTDESK_SERVICE_OWNERSHIP $ServiceOwnedState "$INSTDIR"
  ${If} $ServiceOwnedState == "OWNED"
    DetailPrint "Stopping owned DAUVERSE RustDesk service under $INSTDIR..."
    nsExec::ExecToLog 'sc.exe stop RustDesk'
    Pop $0
  ${ElseIf} $ServiceOwnedState == "EXTERNAL"
    DetailPrint "External RustDesk service detected outside $INSTDIR — preserving untouched."
  ${EndIf}

  ; F03: Stop ONLY processes whose executable path starts with $INSTDIR\
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\dauverse_setup_helper.ps1" -Action StopOwnedProcesses -InstallDir "$INSTDIR"'
  Pop $0

  ; F11: Create SHA-256-manifested Rollback Snapshot if upgrading an existing installation
  IfFileExists "$INSTDIR\DAUVERSE_REMOTE.exe" 0 SkipBackup
    DetailPrint "Creating verified upgrade rollback snapshot with BACKUP_SHA256_MANIFEST.txt..."
    nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\dauverse_setup_helper.ps1" -Action CreateVerifiedBackup -InstallDir "$INSTDIR" -HasFixedDriveE "$HasFixedDriveE"'
    Pop $0
    ${If} $0 != 0
      Abort "SAFETY_ABORT: Failed to create verified rollback backup before upgrading $INSTDIR (exit $0)."
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
  !insertmacro CHECK_RUSTDESK_SERVICE_OWNERSHIP $ServiceOwnedState "$INSTDIR"
  ${If} $ServiceOwnedState == "EXTERNAL"
    DetailPrint "COLLISION_REFUSED: External RustDesk Windows Service already exists outside $INSTDIR. Preserving external service untouched."
    Abort "Cannot register Windows Service 'RustDesk': an external RustDesk installation already owns that service name."
  ${EndIf}
  nsExec::ExecToLog 'sc.exe create RustDesk binPath= "\"$INSTDIR\rustdesk.exe\" --service" start= auto DisplayName= "DAUVERSE Remote Desktop Service (RustDesk Engine)"'
  Pop $0
  ${If} $0 != 0
    ${If} $ServiceOwnedState != "OWNED"
      Abort "Failed to create owned Windows Service 'RustDesk' (sc.exe exit $0)."
    ${EndIf}
  ${EndIf}
  nsExec::ExecToLog 'sc.exe failure RustDesk reset= 86400 actions= restart/5000/restart/15000/restart/30000'
  Pop $0
  nsExec::ExecToLog 'sc.exe start RustDesk'
  Pop $0
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop" "OwnedServiceRegistered" "1"
SectionEnd

Section "Uninstall"
  InitPluginsDir
  File "/oname=$PLUGINSDIR\dauverse_setup_helper.ps1" "${__FILEDIR__}\dauverse_setup_helper.ps1"

  ; F03: Verify ImagePath ownership BEFORE stopping or deleting RustDesk service
  !insertmacro CHECK_RUSTDESK_SERVICE_OWNERSHIP $ServiceOwnedState "$INSTDIR"
  ${If} $ServiceOwnedState == "OWNED"
    DetailPrint "Stopping and removing DAUVERSE-owned RustDesk Windows Service..."
    nsExec::ExecToLog 'sc.exe stop RustDesk'
    Pop $0
    nsExec::ExecToLog 'sc.exe delete RustDesk'
    Pop $0
  ${ElseIf} $ServiceOwnedState == "EXTERNAL"
    DetailPrint "Preserving external RustDesk Windows Service untouched (ImagePath outside $INSTDIR)."
  ${EndIf}

  ; F03: Stop ONLY processes whose executable path starts with $INSTDIR\
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\dauverse_setup_helper.ps1" -Action StopOwnedProcesses -InstallDir "$INSTDIR"'
  Pop $0

  ; Remove HKCU Run entry ONLY if owned by $INSTDIR
  ReadRegStr $R4 HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "DauverseRemoteDesktop"
  ${If} $R4 != ""
    StrCpy $R5 $R4 1
    ${If} $R5 == '"'
      StrCpy $R4 $R4 "" 1
    ${EndIf}
    StrLen $R6 "$INSTDIR\"
    StrCpy $R7 $R4 $R6
    ${If} $R7 == "$INSTDIR\"
      DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "DauverseRemoteDesktop"
    ${EndIf}
  ${EndIf}

  Delete "$DESKTOP\DAUVERSE Remote Desktop.lnk"
  RMDir /r "$SMPROGRAMS\DAUVERSE Remote Desktop"
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop"
SectionEnd
