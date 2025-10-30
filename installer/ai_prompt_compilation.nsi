; NSIS script for AI Prompt Compilation (setup.exe)
; Output: dist\AI-Prompt-Compilation-Setup.exe

!include "MUI2.nsh"

!define APPNAME "AI Prompt Compilation"
!define APPVERSION "1.0.2"
!define COMPANY "AI Prompt Dev"
!define OUTFILE "..\\dist\\AI-Prompt-Compilation-Setup-1.0.2.exe"
!define UNINST_KEY "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${APPNAME}"

OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\\${APPNAME}"
RequestExecutionLevel user
Unicode true

VIProductVersion "1.0.2.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "CompanyName" "${COMPANY}"
VIAddVersionKey "FileDescription" "${APPNAME} Installer"
VIAddVersionKey "FileVersion" "${APPVERSION}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "Install"
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /r "..\\build\\windows\\x64\\runner\\Release\\*"
  CreateDirectory "$SMPROGRAMS\\${APPNAME}"
  CreateShortCut "$SMPROGRAMS\\${APPNAME}\\${APPNAME}.lnk" "$INSTDIR\\ai_prompt_compilation.exe" "" "$INSTDIR\\ai_prompt_compilation.exe" 0
  CreateShortCut "$DESKTOP\\${APPNAME}.lnk" "$INSTDIR\\ai_prompt_compilation.exe" "" "$INSTDIR\\ai_prompt_compilation.exe" 0
  ; Write uninstaller
  WriteUninstaller "$INSTDIR\\Uninstall.exe"
  ; Register Apps & Features uninstall entry (HKCU)
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${APPVERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${COMPANY}"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\\ai_prompt_compilation.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ; Start Menu uninstall shortcut
  CreateShortCut "$SMPROGRAMS\\${APPNAME}\\Uninstall ${APPNAME}.lnk" "$INSTDIR\\Uninstall.exe"
SectionEnd

Section "Uninstall"
  ; Remove Start Menu and desktop shortcuts
  Delete "$DESKTOP\\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\\${APPNAME}\\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\\${APPNAME}\\Uninstall ${APPNAME}.lnk"
  RMDir /r "$SMPROGRAMS\\${APPNAME}"
  ; Remove uninstall registry entry
  DeleteRegKey HKCU "${UNINST_KEY}"
  ; Remove installed files and uninstaller
  Delete "$INSTDIR\\Uninstall.exe"
  RMDir /r "$INSTDIR"
SectionEnd