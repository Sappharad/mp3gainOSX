# Microsoft Developer Studio Project File - Name="mp3gain" - Package Owner=<4>
# Microsoft Developer Studio Generated Build File, Format Version 6.00
# ** DO NOT EDIT **

# TARGTYPE "Win32 (x86) Console Application" 0x0103

CFG=mp3gain - Win32 DebugDLL
!MESSAGE This is not a valid makefile. To build this project using NMAKE,
!MESSAGE use the Export Makefile command and run
!MESSAGE 
!MESSAGE NMAKE /f "mp3gain.mak".
!MESSAGE 
!MESSAGE You can specify a configuration when running NMAKE
!MESSAGE by defining the macro CFG on the command line. For example:
!MESSAGE 
!MESSAGE NMAKE /f "mp3gain.mak" CFG="mp3gain - Win32 DebugDLL"
!MESSAGE 
!MESSAGE Possible choices for configuration are:
!MESSAGE 
!MESSAGE "mp3gain - Win32 Release" (based on "Win32 (x86) Console Application")
!MESSAGE "mp3gain - Win32 Debug" (based on "Win32 (x86) Console Application")
!MESSAGE "mp3gain - Win32 ReleaseDLL" (based on "Win32 (x86) Console Application")
!MESSAGE "mp3gain - Win32 DebugDLL" (based on "Win32 (x86) Console Application")
!MESSAGE 

# Begin Project
# PROP AllowPerConfigDependencies 0
# PROP Scc_ProjName ""$/analysis", SCAAAAAA"
# PROP Scc_LocalPath "."
CPP=cl.exe
RSC=rc.exe

!IF  "$(CFG)" == "mp3gain - Win32 Release"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 0
# PROP BASE Output_Dir "Release"
# PROP BASE Intermediate_Dir "Release"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 0
# PROP Output_Dir "Release"
# PROP Intermediate_Dir "Release"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
MTL=midl.exe
# ADD BASE CPP /nologo /W3 /GX /O2 /D "WIN32" /D "NDEBUG" /D "_CONSOLE" /D "_MBCS" /YX /FD /c
# ADD CPP /nologo /W4 /GX /Zi /O2 /Ob2 /D "WIN32" /D "NDEBUG" /D "_CONSOLE" /D "_MBCS" /D "HAVE_MEMCPY" /D "NOANALYSIS" /D "HAVE_STRCHR" /U "asWIN32DLL" /YX /FD /c
# SUBTRACT CPP /WX
# ADD BASE RSC /l 0x409 /d "NDEBUG"
# ADD RSC /l 0x409 /d "NDEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:console /machine:I386
# ADD LINK32 setargv.obj /nologo /subsystem:console /map /debug /machine:I386 /OPT:REF
# SUBTRACT LINK32 /pdb:none

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 1
# PROP BASE Output_Dir "Debug"
# PROP BASE Intermediate_Dir "Debug"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 1
# PROP Output_Dir "Debug"
# PROP Intermediate_Dir "Debug"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
MTL=midl.exe
# ADD BASE CPP /nologo /W3 /Gm /GX /ZI /Od /D "WIN32" /D "_DEBUG" /D "_CONSOLE" /D "_MBCS" /YX /FD /GZ /c
# ADD CPP /nologo /W3 /Gm /GX /Zi /Od /D "WIN32" /D "_DEBUG" /D "_CONSOLE" /D "_MBCS" /D "HAVE_MEMCPY" /D "NOANALYSIS" /YX /FD /GZ /c
# ADD BASE RSC /l 0x409 /d "_DEBUG"
# ADD RSC /l 0x409 /d "_DEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:console /debug /machine:I386 /pdbtype:sept
# ADD LINK32 setargv.obj /nologo /subsystem:console /incremental:no /map /debug /machine:I386 /pdbtype:sept

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 0
# PROP BASE Output_Dir "ReleaseDLL"
# PROP BASE Intermediate_Dir "ReleaseDLL"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 0
# PROP Output_Dir "ReleaseDLL"
# PROP Intermediate_Dir "ReleaseDLL"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
MTL=midl.exe
# ADD BASE MTL /nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32
# ADD MTL /nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32
# ADD BASE CPP /nologo /MT /W3 /GX /O2 /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /FD /c
# ADD CPP /nologo /MD /W4 /GX /Zi /O2 /Ob2 /D "NDEBUG" /D "asWIN32DLL" /D "WIN32" /D "_WINDOWS" /D "HAVE_MEMCPY" /D "NOANALYSIS" /FR /FD /c
# ADD BASE RSC /l 0x409 /d "NDEBUG"
# ADD RSC /l 0x409 /d "NDEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:windows /dll /machine:I386
# ADD LINK32 user32.lib /nologo /base:"0x60000000" /subsystem:windows /dll /map /debug /machine:I386 /nodefaultlib:"LIBC" /def:"replaygaindll.def" /out:"ReleaseDLL/replaygain.dll" /OPT:REF
# SUBTRACT LINK32 /pdb:none

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 0
# PROP BASE Output_Dir "DebugDLL"
# PROP BASE Intermediate_Dir "DebugDLL"
# PROP BASE Ignore_Export_Lib 0
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 0
# PROP Output_Dir "DebugDLL"
# PROP Intermediate_Dir "DebugDLL"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
MTL=midl.exe
# ADD BASE MTL /nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32
# ADD MTL /nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32
# ADD BASE CPP /nologo /Zp1 /MD /W3 /GX /Zi /Od /D "WIN32" /D "_WINDOWS" /FR /FD /c
# ADD CPP /nologo /MD /W4 /GX /Zi /Od /D "WIN32" /D "_WINDOWS" /D "_MBCS" /D "HAVE_MEMCPY" /D "NOANALYSIS" /D "asWIN32DLL" /FR /FD /c
# ADD BASE RSC /l 0x409 /d "NDEBUG"
# ADD RSC /l 0x409 /d "NDEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:windows /dll /map /debug /machine:I386 /def:"replaygaindll.def"
# SUBTRACT BASE LINK32 /verbose /pdb:none
# ADD LINK32 user32.lib /nologo /base:"0x60000000" /subsystem:windows /dll /incremental:yes /map /debug /machine:I386 /nodefaultlib:"LIBC" /def:"replaygaindll.def" /out:"DebugDLL/replaygain.dll"
# SUBTRACT LINK32 /verbose /pdb:none

!ENDIF 

# Begin Target

# Name "mp3gain - Win32 Release"
# Name "mp3gain - Win32 Debug"
# Name "mp3gain - Win32 ReleaseDLL"
# Name "mp3gain - Win32 DebugDLL"
# Begin Group "Source Files"

# PROP Default_Filter ".c"
# Begin Source File

SOURCE=.\apetag.c
# End Source File
# Begin Source File

SOURCE=.\id3tag.c
# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\common.c

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\dct64_i386.c

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\decode_i386.c

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\gain_analysis.c
# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\interface.c

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\layer3.c

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mp3gain.c
# End Source File
# Begin Source File

SOURCE=.\replaygaindll.c

!IF  "$(CFG)" == "mp3gain - Win32 Release"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\rg_error.c
# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\tabinit.c

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# End Group
# Begin Group "Header Files"

# PROP Default_Filter ".h"
# Begin Source File

SOURCE=.\apetag.h
# End Source File
# Begin Source File

SOURCE=.\id3tag.h
# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\bitstream.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\common.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\config.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\dct64_i386.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\decode_i386.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\encoder.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\gain_analysis.h
# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\huffman.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\interface.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\lame.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\layer3.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\machine.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mp3gain.h
# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\mpg123.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\mpglib.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\resource.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\rg_error.h
# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\tabinit.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\mpglibDBL\VbrTag.h

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# End Group
# Begin Group "Resource Files"

# PROP Default_Filter ".rc"
# Begin Source File

SOURCE=.\replaygaindll.def

!IF  "$(CFG)" == "mp3gain - Win32 Release"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\replaygainversion.rc

!IF  "$(CFG)" == "mp3gain - Win32 Release"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\VerInfo.rc

!IF  "$(CFG)" == "mp3gain - Win32 Release"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 Debug"

!ELSEIF  "$(CFG)" == "mp3gain - Win32 ReleaseDLL"

# PROP Exclude_From_Build 1

!ELSEIF  "$(CFG)" == "mp3gain - Win32 DebugDLL"

# PROP Exclude_From_Build 1

!ENDIF 

# End Source File
# End Group
# End Target
# End Project
