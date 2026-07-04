# Included by electron-builder (nsis.include). customInstall runs after the
# payload is extracted and the shortcuts exist, but BEFORE the one-click
# installer auto-launches the app via the Start Menu shortcut. Without this
# check, a missing executable — most commonly Windows Defender quarantining
# the not-yet-code-signed binary right after extraction — surfaces as the
# shell's baffling "Missing Shortcut: Windows is searching for Syrus.exe"
# dialog instead of an actionable error.
!macro customInstall
  ${ifNot} ${FileExists} "$INSTDIR\${APP_EXECUTABLE_FILENAME}"
    ${ifNot} ${Silent}
      MessageBox MB_ICONSTOP "Syrus installed, but its main program is missing from:$\r$\n$INSTDIR$\r$\n$\r$\nThis usually means Windows Defender quarantined the app right after install (Syrus for Windows is not code-signed yet). Open Windows Security > Protection history, restore or allow Syrus — or add an exclusion for the folder above — then run this installer again."
    ${endIf}
    SetErrorLevel 2
    Quit
  ${endIf}
!macroend
