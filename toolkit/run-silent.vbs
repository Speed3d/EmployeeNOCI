Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
backendDir = fso.GetParentFolderName(scriptDir) & "\backend"

WshShell.CurrentDirectory = backendDir
WshShell.Run "cmd /c node src/app.js", 0, False
