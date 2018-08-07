; An x64 Windows tray application that uses a hotkey to mute or unmute the
; default capture device and play a sound upon toggle. Written using FASM.
; Copyright (c) 2018, Ryan Sweet
; All rights reserved.

format PE64 GUI 5.0
entry start
include 'win64a.inc'

; GUID macro taken from Tomasz Grysztar's USECOM.ASM in fasm examples.
struc GUID def {
  match d1-d2-d3-d4-d5, def \{
    .Data1 dd 0x\#d1
    .Data2 dw 0x\#d2
    .Data3 dw 0x\#d3
    .Data4 db 0x\#d4 shr 8,0x\#d4 and 0FFh
    .Data5 db 0x\#d5 shr 40,0x\#d5 shr 32 and 0FFh,0x\#d5 shr 24 and 0FFh,0x\#d5 shr 16 and 0FFh,0x\#d5 shr 8 and 0FFh,0x\#d5 and 0FFh
  \}
}

; COM definitions for mmdeviceapi
interface IMMDeviceEnumerator,\
  QueryInterface,\
  AddRef,\
  Release,\
  EnumAudioEndpoints,\
  GetDefaultAudioEndpoint,\
  GetDevice,\
  RegisterEndpointNotificationCallback,\
  UnregisterEndpointNotificationCallback

interface IMMDevice,\
  QueryInterface,\
  AddRef,\
  Release,\
  Activate,\
  OpenPropertyStore,\
  GetId,\
  GetState

interface IAudioEndpointVolume,\
  QueryInterface,\
  AddRef,\
  Release,\
  RegisterControlChangeNotify,\
  UnregisterControlChangeNotify,\
  GetChannelCount,\
  SetMasterVolumeLevel,\
  SetMasterVolumeLevelScalar,\
  GetMasterVolumeLevel,\
  GetMasterVolumeLevelScalar,\
  SetChannelVolumeLevel,\
  SetChannelVolumeLevelScalar,\
  GetChannelVolumeLevel,\
  GetChannelVolumeLevelScalar,\
  SetMute,\
  GetMute,\
  GetVolumeStepInfo,\
  VolumeStepUp,\
  VolumeStepDown,\
  QueryHardwareSupport,\
  GetVolumeRange

; constants
CLSCTX_INPROC_SERVER     = 0x1
COINIT_APARTMENTTHREADED = 0x2
HK_F12                   = 2
IDI_TRAY                 = 0
IDM_EXIT                 = 100
ID_SHOW                  = 100
ID_HIDE                  = 101
E_CONSOLE                = 0
E_CAPTURE                = 1
WM_SHELLNOTIFY           = WM_USER+5

section '.text' code readable executable
start:
  sub     rsp,8 ; align stack to 16 bytes

  invoke  CoInitializeEx,NULL,COINIT_APARTMENTTHREADED
  test    rax,rax
  jnz     error

  invoke  GetModuleHandle,NULL
  mov     [wc.hInstance],rax

  invoke  RegisterClassEx,wc
  test    rax,rax
  jz      error

  invoke  CreateWindowEx,0,szClass,szTitle,0,0,0,0,0,HWND_DESKTOP,NULL,[wc.hInstance],NULL
  test    rax,rax
  jz      error

  mov     [hWnd],rax

  invoke  RegisterHotKey,[hWnd],HK_F12,MOD_ALT+MOD_CONTROL,VK_F12
  test    rax,rax
  jz      error

message_loop:
  invoke  GetMessage,msg,NULL,0,0
  test    rax,rax
  jz      finish
  invoke  TranslateMessage,msg
  invoke  DispatchMessage,msg
  jmp     message_loop

error:
  invoke  MessageBox,NULL,szError,NULL,MB_ICONERROR+MB_OK

finish:
  invoke  UnregisterHotKey,[hWnd],HK_F12
  invoke  CoUninitialize
  invoke  ExitProcess,NULL

proc WindowProc; rcx = hWnd, rdx = uMsg, r8 = wParam, r9 = lParam
local pt:POINT
  cmp     rdx,WM_HOTKEY
  je      .wmhotkey
  cmp     rdx,WM_SHELLNOTIFY
  je      .wmshellnotify
  cmp     rdx,WM_COMMAND
  je      .wmcommand
  cmp     rdx,WM_CREATE
  je      .wmcreate
  cmp     rdx,WM_DESTROY
  je      .wmdestroy
.defwindowproc:
  invoke  DefWindowProc,rcx,rdx,r8,r9
  jmp     .finish
.wmcommand:; WM_COMMAND handler - process the clicks from the tray icon
  cmp     r8,IDM_EXIT
  jne     .finish
  invoke  DestroyWindow,rcx
  jmp     .finish
.wmcreate:
; create tray icon
  mov     [notify.hWnd],rcx
  invoke  LoadIcon,NULL,IDI_APPLICATION
  mov     [notify.hIcon],rax
  invoke  Shell_NotifyIcon,NIM_ADD,notify
  invoke  CreatePopupMenu
  mov     [hTrayMenu],rax
  invoke  AppendMenu,rax,MF_STRING,IDM_EXIT,szExit
  xor     rax,rax
  jmp     .finish
.wmdestroy:
  invoke  Shell_NotifyIcon,NIM_DELETE,notify
  invoke  DestroyMenu,[hTrayMenu]
  invoke  PostQuitMessage,0
  xor     rax,rax
  jmp     .finish
.wmshellnotify:  ; WM_SHELLNOTIFY handler - process the tray
  cmp     r9,WM_RBUTTONDOWN
  jne     .finish
  ; show the tray menu on right click
  lea     rax,[pt]
  invoke  GetCursorPos,rax
  invoke  SetForegroundWindow,rcx
  ; I suspect we need to pass [hWnd] instead of rcx because rcx=menu handle when .wmshellnotify
  invoke  TrackPopupMenu,[hTrayMenu],TPM_RIGHTALIGN,[pt.x],[pt.y],0,[hWnd],NULL
  invoke  PostMessage,rcx,WM_NULL,0,0
  xor     rax,rax
  jmp     .finish
.wmhotkey:
  ; get multimedia device enumerator
  invoke  CoCreateInstance,CLSID_MMDeviceEnumerator,NULL,CLSCTX_INPROC_SERVER,IID_IMMDeviceEnumerator,DeviceEnumerator
  test    rax,rax
  jnz     .finish
  cmp     [DeviceEnumerator],0
  jz      .finish

  ; get default capture device
  cominvk DeviceEnumerator,GetDefaultAudioEndpoint,E_CAPTURE,E_CONSOLE,Device
  test    rax,rax
  jnz     .freeenumerator
  cmp     [Device],0
  jz      .freeenumerator

  ; get the IAudioEndpointVolume control for the default capture device
  cominvk Device,Activate,IID_IAudioEndpointVolume,CLSCTX_INPROC_SERVER,NULL,Volume
  test    rax,rax
  jnz     .freedevice
  cmp     [Volume],0
  jz      .freedevice

  ; get the mute state
  cominvk Volume,GetMute,isMute

  ; isMute = !isMute
  mov     eax,[isMute]
  not     eax
  and     eax,1
  mov     [isMute],eax

  ; set the mute state
  cominvk Volume,SetMute,[isMute],NULL

  ; release the IAudioEndpointVolume control
  cominvk Volume,Release

  ; which sound should we play?
  mov     eax,[isMute]
  test    eax,eax
  jnz     .mute
  mov     rcx,szPlayUnmute
  jmp     .play
.mute:
  mov     rcx,szPlayMute
.play:
  invoke  mciSendString,rcx,NULL,0,0
.freedevice:
  cominvk Device,Release
.freeenumerator:
  cominvk DeviceEnumerator,Release
.finish:
  ret
endp

section '.data' data readable writeable
IID_IMMDeviceEnumerator   GUID A95664D2-9614-4F35-A746-DE8DB63617E6
CLSID_MMDeviceEnumerator  GUID BCDE0395-E52F-467C-8E3D-C4579291692E
IID_IAudioEndpointVolume  GUID 5CDF2C82-841E-4546-9722-0CF74078229A
DeviceEnumerator          IMMDeviceEnumerator
Device                    IMMDevice
Volume                    IAudioEndpointVolume
wc                        WNDCLASSEX sizeof.WNDCLASSEX,0,WindowProc,0,0,NULL,NULL,NULL,COLOR_BTNFACE+1,NULL,szClass,NULL
notify                    NOTIFYICONDATA sizeof.NOTIFYICONDATA,NULL,IDI_TRAY,NIF_ICON+NIF_MESSAGE+NIF_TIP,WM_SHELLNOTIFY,NULL,'Mute'
hTrayMenu                 dq ?
hWnd                      dq ?
isMute                    dd ?
msg                       MSG
szPlayMute                TCHAR "play mute.mp3",0
szPlayUnmute              TCHAR "play unmute.mp3",0
szClass                   TCHAR "Mute",0
szError                   TCHAR "Error during startup",0
szExit                    TCHAR "&Exit",0
szTitle                   TCHAR "Mute",0

section '.idata' import data readable
library kernel32,'KERNEL32.DLL',\
  user32,'USER32.DLL',\
  shell32,'SHELL32.DLL',\
  ole32,'OLE32.DLL',\
  winmm,'WINMM.DLL'

import ole32,\
  CoCreateGuid,'CoCreateGuid',\
  CoInitialize,'CoInitialize',\
  CoInitializeEx,'CoInitializeEx',\
  CoCreateInstance,'CoCreateInstance',\
  CoUninitialize,'CoUninitialize'

import winmm,\
  mciSendString,'mciSendStringA'

include 'api/kernel32.inc'
include 'api/user32.inc'
include 'api/shell32.inc'
