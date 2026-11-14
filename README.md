# Clust releases

Signed binaries of [Clust](https://github.com/YuriAlvesBordin/clust), a terminal AI coding agent written in Rust.

This repository holds release binaries only. There is no source code here.

## Install

Download the binary for your system from the latest release, make it executable and run it:

```sh
chmod +x clust-<target>
./clust-<target> login
```

Each binary comes with a `.sig` file. Once installed, `clust update` fetches new releases from here and verifies the signature.
