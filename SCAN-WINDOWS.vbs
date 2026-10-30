' ==============================================================================
' SCAN-WINDOWS.vbs
' TechDesk USB Scanner - Lancement en 1 clic SANS fenetre terminal
'
' Double-cliquez sur ce fichier sous Windows pour lancer le scan en arriere-plan.
' Une boite de dialogue native s'affiche a la fin avec le resultat du scan.
' ==============================================================================
Option Explicit
Dim objShell, fso, strDir, psCmd1, psCmd2, exit1, exit2, logFile, resultMsg, ts

Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
strDir = fso.GetParentFolderName(WScript.ScriptFullName)

logFile = objShell.ExpandEnvironmentStrings("%TEMP%") & "\techdesk-scan-" & objShell.ExpandEnvironmentStrings("%RANDOM%") & ".txt"

' 1/2 - Stock TechDesk (0 = fenetre invisible, True = synchrone)
psCmd1 = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& '" & strDir & "\scanner\scan-windows.ps1' *>> '" & logFile & "'"""
exit1 = objShell.Run(psCmd1, 0, True)

' 2/2 - Fiche technique & journal CSV (0 = fenetre invisible, True = synchrone)
psCmd2 = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& '" & strDir & "\fiche-technique\outils\fiche-windows.ps1' *>> '" & logFile & "'"""
exit2 = objShell.Run(psCmd2, 0, True)

' Recuperation du resultat
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

If InStr(resultMsg, "AJOUTE AU STOCK") > 0 Or InStr(resultMsg, "AJOUTÉ AU STOCK") > 0 Then
    objShell.Popup "NOUVEAU LAPTOP AJOUTE AU STOCK TECHDESK !" & vbCrLf & vbCrLf & _
                   "- Fiche technique enregistree dans le journal CSV" & vbCrLf & _
                   "- Synchronise avec TechDesk" & vbCrLf & vbCrLf & _
                   "(Fermeture automatique dans 15 secondes)", 15, "TechDesk USB Scanner", 64
ElseIf InStr(resultMsg, "DEJA EN STOCK") > 0 Or InStr(resultMsg, "DÉJÀ EN STOCK") > 0 Then
    objShell.Popup "CE LAPTOP EST DEJA EN STOCK TECHDESK" & vbCrLf & vbCrLf & _
                   "- Fiche technique actualisee dans le journal CSV" & vbCrLf & _
                   "- Synchronise avec TechDesk" & vbCrLf & vbCrLf & _
                   "(Fermeture automatique dans 15 secondes)", 15, "TechDesk USB Scanner", 64
ElseIf exit1 = 0 And exit2 = 0 Then
    objShell.Popup "Scan termine avec succes !" & vbCrLf & vbCrLf & _
                   "- Laptop enregistre au stock" & vbCrLf & _
                   "- Fiche technique ajoutee au journal CSV", 15, "TechDesk USB Scanner", 64
Else
    objShell.Popup "Scan termine !" & vbCrLf & vbCrLf & _
                   "Les donnees sont enregistrees localement sur la cle USB." & vbCrLf & _
                   "Si ce laptop n'a pas de connexion Internet, le scan partira automatiquement lors du prochain scan connecte.", 15, "TechDesk USB Scanner", 48
End If
