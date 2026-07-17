# DreamSkin.exe

`DreamSkin.exe` is a small Windows Forms controller for the Windows Codex Dream Skin.

The application icon is generated from the repository image `image-studio-task-mrmx8vxv-ngo98z5.png` and embedded as `DreamSkin.ico`.

It lets you:

- choose a PNG, JPG, JPEG, or WebP background image;
- choose adaptive neutral, light glass, or dark glass styling;
- apply the user theme through the existing loopback CDP injector;
- restore the live Codex UI and open the user theme directory.

The generated standalone artifact is placed at `windows/DreamSkin.exe`.

To rebuild it from source:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\build-dream-skin.ps1
```

The default build is self-contained for `win-x64`. Use `-FrameworkDependent` for a smaller build that requires the .NET 7 Desktop Runtime.
