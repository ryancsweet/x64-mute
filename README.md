# x64-mute
An x86-64 Windows tray application that uses a hotkey to mute / unmute the default capture device and play a sound upon toggle.

This project showcases a number of things:
- A Windows tray application with a right-click handler for handling the Exit message
- Registering a global hotkey
- COM interop with the [Core Audio Interfaces](https://docs.microsoft.com/en-us/windows/desktop/CoreAudio/core-audio-interfaces)
- Sound playback using [MCI](https://docs.microsoft.com/en-us/windows/desktop/Multimedia/about-mci)
- Compiles to 4096 bytes using FASM 1.72

## Build

> fasm mute.asm

## How Do I use it?
- Toggle mute or unmute on your default capture device using `CTRL-ALT-F12`
- It will play sounds from `mute.mp3` or `unmute.mp3` if you include them alongside `mute.exe`

## Why is this a thing?

I wanted to learn x64 assembly and within a couple hours this application was complete.

## Credits

I would like to thank Tomasz Grysztar, the author of FASM assembler.