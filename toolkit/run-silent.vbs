Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
backendDir = fso.GetParentFolderName(scriptDir) & "\backend"

WshShell.CurrentDirectory = backendDir
' Supervisor: restarts the server automatically and writes backend\logs\server.log
WshShell.Run "cmd /c node scripts/run-forever.js", 0, False
