# Clust releases

Signed binaries of [Clust](https://github.com/YuriAlvesBordin/clust), a terminal AI coding agent written in Rust.

This repository holds release binaries and the installers only. There is no source code here.

## Install

macOS and Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/YuriAlvesBordin/clust-releases/main/install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/YuriAlvesBordin/clust-releases/main/install.ps1 | iex
```

Then open a new terminal and run `clust login`.

The installer picks the build for your system, checks its signature with the same key `clust update` uses, puts `clust` in `~/.local/bin` (Windows: `%LOCALAPPDATA%\Programs\clust`) and adds that folder to your PATH. No admin rights are needed. On macOS and Linux the signature check needs OpenSSL 3; without it the installer says so and relies on the HTTPS download from GitHub.

Options, as environment variables:

| Variable | Effect |
|---|---|
| `CLUST_VERSION=v0.1.4` | Install that release instead of the latest |
| `CLUST_INSTALL_DIR=/some/dir` | Install somewhere else |
| `CLUST_NO_MODIFY_PATH=1` | Never change PATH or shell profiles |

Running the installer again updates Clust. Once installed, `clust update` does the same.

## Manual download

Each release has, per system, an archive (`.tar.gz`, or `.zip` on Windows) for downloading by hand, plus the bare binary and its `.sig` that the installers and `clust update` use. Extract the archive and run `./clust login`.
