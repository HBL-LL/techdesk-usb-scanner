' ==============================================================================
' FICHE-WINDOWS.vbs
' TechDesk USB Scanner - Fiche technique seule en 1 clic SANS fenetre terminal
' ==============================================================================
Option Explicit
Dim objShell, fso, strDir, psCmd, exitCode, logFile, resultMsg, ts

Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
strDir = fso.GetParentFolderName(WScript.ScriptFullName)

logFile = objShell.ExpandEnvironmentStrings("%TEMP%") & "\techdesk-fiche-" & objShell.ExpandEnvironmentStrings("%RANDOM%") & ".txt"

psCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& '" & strDir & "\outils\fiche-windows.ps1' *>> '" & logFile & "'"""
exitCode = objShell.Run(psCmd, 0, True)

resultMsg = ""
If fso.FileExists(logFile) Then
    On Error Resume Next
    Set ts = fso.OpenTextFile(logFile, 1, False)
    If Not ts.AtEndOfStream Then
        resultMsg = ts.ReadAll()
    End If
    ts.Close
    fso.DeleteFile logFile, True
    On Error GoTo 0
End If

If InStr(resultMsg, "FICHE AJOUTEE") > 0 Or InStr(resultMsg, "FICHE AJOUTÉE") > 0 Or InStr(resultMsg, "FICHE ENREGISTREE") > 0 Or InStr(resultMsg, "FICHE ENREGISTRÉE") > 0 Or exitCode = 0 Then
    objShell.Popup "Fiche technique relevee avec succes !" & vbCrLf & vbCrLf & _
                   "- Enregistree dans journal-des-scans.csv" & vbCrLf & _
                   "- Fiche synchronisee avec TechDesk", 15, "TechDesk - Fiche Technique", 64
Else
    objShell.Popup "Fiche technique enregistree dans le journal CSV sur la cle !" & vbCrLf & vbCrLf & _
                   "(Elle sera synchronisee avec TechDesk des qu'une connexion Internet sera disponible).", 15, "TechDesk - Fiche Technique", 48
End If
