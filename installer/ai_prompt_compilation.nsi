; NSIS script for AI Prompt Compilation (setup.exe)
; Output: dist\AI-Prompt-Compilation-Setup.exe

!include "MUI2.nsh"

!define APPNAME "AI Prompt Compilation"
!define APPVERSION "1.0.0"
!define COMPANY "AI Prompt Dev"
!define OUTFILE "..\\dist\\AI-Prompt-Compilation-Setup.exe"

OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\\${APPNAME}"
RequestExecutionLevel user
Unicode true

VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "CompanyName" "${COMPANY}"
VIAddVersionKey "FileDescription" "${APPNAME} Installer"
VIAddVersionKey "FileVersion" "${APPVERSION}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "SimpChinese"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "..\\build\\windows\\x64\\runner\\Release\\*"
  CreateDirectory "$SMPROGRAMS\\${APPNAME}"
  CreateShortCut "$SMPROGRAMS\\${APPNAME}\\${APPNAME}.lnk" "$INSTDIR\\ai_prompt_compilation.exe" "" "$INSTDIR\\ai_prompt_compilation.exe" 0
  CreateShortCut "$DESKTOP\\${APPNAME}.lnk" "$INSTDIR\\ai_prompt_compilation.exe" "" "$INSTDIR\\ai_prompt_compilation.exe" 0
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\\${APPNAME}\\${APPNAME}.lnk"
  RMDir /r "$SMPROGRAMS\\${APPNAME}"
  RMDir /r "$INSTDIR"
SectionEnd