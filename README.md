# Fortnite Booster by StrixLuca

A free, open source Fortnite booster that makes the game run smoother and gives you more FPS. It works on any PC, any graphics card and any processor. No installer, no background processes, no account risk.

**Version 1.0 beta**

---

## What it does

- Applies fast, competitive Fortnite graphics settings (shadows, effects, motion blur, render mode, resolution, FPS limit) and backs up your config first.
- Tunes safe Windows options that every optimization guide mentions: Game Mode, Hardware Accelerated GPU Scheduling, power plan, Game DVR, mouse and keyboard responsiveness, and network settings.
- Can lock your Fortnite config as read only so the game stops wiping your settings every time it launches. While it is locked you change your settings inside the app instead.
- Gives you a full toolkit: a score with a plain explanation of every point, a benchmark to prove the gain, backups and restore, a driver check, a ping test, stretched resolution help, and more.

## What it does not do

No cheats. No aimbot or ESP. It does not inject anything into Fortnite and it never touches Easy Anti Cheat or BattlEye. The only network calls it makes are an optional update check on GitHub and an optional ping test. Your account stays safe.

## Is it safe?

Yes, and you do not have to take our word for it. Everything it changes is a config file or a Windows setting you could edit by hand. A backup is made before every boost, everything can be undone, and the whole project is open source. Every function in the code has a short comment above it explaining exactly what it changes and why. Nothing is hidden or obfuscated.

## How to use it

1. Download the latest release and unzip it.
2. Close Fortnite and the Epic Games Launcher.
3. Double click `StrixBooster.bat`.
4. Click **Yes** on the administrator prompt (needed for the Windows tweaks).
5. The app opens in its own window. First time, you get a short guided tour.
6. Click **Boost my Fortnite**, then start the game.

## Requirements

- Windows 10 or 11
- PowerShell (built into Windows)
- Microsoft Edge (built into Windows) or Google Chrome

Nothing else to install.

## Files in this project

| File | What it is |
|------|-----------|
| `StrixBooster.ps1` | The engine. Reads your system, applies the tweaks, serves the interface. Fully commented. |
| `ui.html` | The interface you see. Plain HTML, CSS and JavaScript. |
| `StrixBooster.bat` | The launcher. Asks for admin rights and starts the app. |
| `README.md` | This file. |
| `LICENSE` | The license. |

## Languages

English, Nederlands, Deutsch and Espanol, switchable in the top right corner.

## Beta

This is a 1.0 beta. It is stable and tested, but if you run into anything, open an issue on GitHub. Feedback during the beta shapes what comes next.

## License

Free to use. See `LICENSE`.
