Set sh = CreateObject("WScript.Shell")
' Start = fresh start: end a stuck or hidden copy first, so this always works
On Error Resume Next
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
For Each p In wmi.ExecQuery("Select * from Win32_Process where Name='powershell.exe'")
  If InStr(p.CommandLine, "-STA -WindowStyle Hidden -File") > 0 And InStr(p.CommandLine, "Luftwaechter.ps1") > 0 Then p.Terminate
Next
On Error GoTo 0
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dir & "\Luftwaechter.ps1""", 0, False
