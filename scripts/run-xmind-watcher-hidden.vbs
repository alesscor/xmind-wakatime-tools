' Launch the watcher completely hidden via Task Scheduler or manual
Option Explicit
Dim shell, fso
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

Dim scriptDir, ps1
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptDir & "\xmind-wakatime-watcher.ps1"

' Early bootstrap log: entry and arg count
Dim bootInit, bootInitDir, lfInit
bootInit = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\WakaTime\watcher-bootstrap.log")
bootInitDir = fso.GetParentFolderName(bootInit)
On Error Resume Next
If Not fso.FolderExists(bootInitDir) Then fso.CreateFolder(bootInitDir)
Set lfInit = fso.OpenTextFile(bootInit, 8, True)
lfInit.WriteLine "[" & Now & "] run-watcher-hidden: enter, args.count=" & CStr(WScript.Arguments.Count)
lfInit.Close
On Error GoTo 0

' Extract desired -WatchPath from arguments (to allow multiple instances for different folders)
Dim desiredWatchPath, iArg
desiredWatchPath = ""
For iArg = 0 To WScript.Arguments.Count - 2
  If LCase(CStr(WScript.Arguments(iArg))) = "-watchpath" Then
    desiredWatchPath = CStr(shell.ExpandEnvironmentStrings(CStr(WScript.Arguments(iArg + 1))))
    Exit For
  End If
Next
If desiredWatchPath <> "" Then
  On Error Resume Next
  desiredWatchPath = fso.GetAbsolutePathName(desiredWatchPath)
  On Error GoTo 0
End If

If Not fso.FileExists(ps1) Then
  Dim bootLogMissing, bootDirMissing, lfMissing
  bootLogMissing = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\WakaTime\watcher-bootstrap.log")
  bootDirMissing = fso.GetParentFolderName(bootLogMissing)
  On Error Resume Next
  If Not fso.FolderExists(bootDirMissing) Then fso.CreateFolder(bootDirMissing)
  Set lfMissing = fso.OpenTextFile(bootLogMissing, 8, True)
  lfMissing.WriteLine "[" & Now & "] run-watcher-hidden: ps1 missing: " & ps1
  lfMissing.Close
  On Error GoTo 0
  WScript.Quit 1
End If

Dim svc, procs, q, already
On Error Resume Next
Set svc = GetObject("winmgmts:\\.\root\cimv2")
If Err.Number = 0 Then
  q = "SELECT CommandLine, Name FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'"
  already = False
  For Each procs In svc.ExecQuery(q)
    Dim cmdline
    cmdline = ""
    On Error Resume Next
    If Not IsNull(procs.CommandLine) Then cmdline = CStr(procs.CommandLine)
    On Error GoTo 0
    If cmdline <> "" Then
      If InStr(1, cmdline, ps1, vbTextCompare) > 0 Then
        If desiredWatchPath <> "" Then
          If InStr(1, cmdline, desiredWatchPath, vbTextCompare) > 0 Then already = True
        Else
          ' If we can't parse desired watch path, fall back to old single-instance behavior
          already = True
        End If
      End If
    End If
    If already Then Exit For
  Next
  If already Then
    Dim bootLogAlready, bootDirAlready, lfAlready
    bootLogAlready = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\WakaTime\watcher-bootstrap.log")
    bootDirAlready = fso.GetParentFolderName(bootLogAlready)
    On Error Resume Next
    If Not fso.FolderExists(bootDirAlready) Then fso.CreateFolder(bootDirAlready)
    Set lfAlready = fso.OpenTextFile(bootLogAlready, 8, True)
    lfAlready.WriteLine "[" & Now & "] run-watcher-hidden: already running, skip. ps1=" & ps1 & " watchPath=" & desiredWatchPath
    lfAlready.Close
    On Error GoTo 0
    WScript.Quit 0
  End If
End If
On Error GoTo 0

Dim args, a, expanded, idx
args = ""
idx = 0
For Each a In WScript.Arguments
  On Error Resume Next
  expanded = CStr(shell.ExpandEnvironmentStrings(CStr(a)))
  ' per-arg bootstrap
  Set lfInit = fso.OpenTextFile(bootInit, 8, True)
  lfInit.WriteLine "[" & Now & "] arg[" & CStr(idx) & "] raw=" & CStr(a) & " expanded=" & expanded
  lfInit.Close
  On Error GoTo 0
  If InStr(expanded, " ") > 0 Then
    args = args & " " & Chr(34) & expanded & Chr(34)
  Else
    args = args & " " & expanded
  End If
  idx = idx + 1
Next

Dim cmd
' Log before composing command
On Error Resume Next
Set lfInit = fso.OpenTextFile(bootInit, 8, True)
lfInit.WriteLine "[" & Now & "] about-to-compose: ps1=" & ps1 & " argsLen=" & Len(args)
lfInit.Close
On Error GoTo 0

cmd = "powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & ps1 & Chr(34) & args

' Bootstrap log for diagnostics
Dim bootLog, bootDir, lf
bootLog = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\WakaTime\watcher-bootstrap.log")
bootDir = fso.GetParentFolderName(bootLog)
On Error Resume Next
If Not fso.FolderExists(bootDir) Then fso.CreateFolder(bootDir)
Set lf = fso.OpenTextFile(bootLog, 8, True)
lf.WriteLine "[" & Now & "] run-watcher-hidden: ps1=" & ps1 & " args=" & args
lf.Close

Set lf = fso.OpenTextFile(bootLog, 8, True)
lf.WriteLine "[" & Now & "] composed-cmd: " & cmd
lf.Close

On Error Resume Next
shell.Run cmd, 0, False
Dim runErr, runDesc
runErr = Err.Number
runDesc = Err.Description
On Error GoTo 0
If runErr <> 0 Then
  Set lf = fso.OpenTextFile(bootLog, 8, True)
  lf.WriteLine "[" & Now & "] run-error: " & CStr(runErr) & " :: " & runDesc
  lf.Close
End If
On Error GoTo 0
