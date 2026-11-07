# Dynamic left reservation in niri 26.04

`0001-preserve-view-relative-to-work-area.patch` targets upstream niri commit
`8ed0da44d974c32c6877d2f4630c314da0717ecb` (reported as `26.04 (8ed0da4)`).

When a left layer-shell reservation shrinks, niri recomputes column sizes but its
fit-to-view logic keeps the old scroll position if the focused column still fits.
This leaves the former sidebar space empty until another action scrolls the view.
Changing a QML exclusive zone or forcing a surface configure cannot correct that
viewport decision.

The patch shifts the viewport by the change in the usable area's left edge before
niri applies its ordinary fitting/centering rules. Fullscreen geometry is exempt;
saved offsets for restoring normal windows are adjusted too.

Apply the patch to the source used by the desktop's niri package, rebuild using
that package's normal features/dependencies, install the rebuilt package, and
start a new niri session. **Installing Pond alone does not apply this patch.**
Do not install the telemetry patch from `tests/zen-layout`, and do not use its
`--no-default-features` test build as a desktop package replacement.

For a source checkout at the matching commit:

```sh
git apply --check /path/to/pond-interface/config/niri/patches/0001-preserve-view-relative-to-work-area.patch
git apply /path/to/pond-interface/config/niri/patches/0001-preserve-view-relative-to-work-area.patch
```

## Arch package `niri 26.04-1`

`arch/PKGBUILD` is based on the official Arch packaging tag `26.04-1`, commit
`2f67848d363d8cf6f49f7264b04a3443c8a941fa`. It retains the official dependencies,
default features, test suite, source checksums, and installed files. It adds the
checksummed viewport patch, changes the local release to `26.04-1.1`, and marks
`niri --version` with `-pond1`. A later official package release can supersede it.

Run on the Arch desktop, from the Pond checkout, as your ordinary user:

```sh
sudo pacman -S --needed base-devel
build_dir=$(mktemp -d "$HOME/niri-pond-fix.XXXXXX")
cp config/niri/patches/arch/PKGBUILD config/niri/patches/0001-preserve-view-relative-to-work-area.patch "$build_dir/"
cd "$build_dir"
makepkg -si
```

`makepkg -si` installs missing build dependencies, builds and tests the package,
then asks pacman to install it. It needs network access and considerable build
space; sudo is used for dependency/package installation, not compilation. Save
work and log out/in after installation: replacing `/usr/bin/niri` does not change
the running compositor. `niri --version` should then contain `8ed0da4-pond1`.
Keep the Pond sidebar changes from this checkout installed as well.

The package recipe was syntax-checked and its patch/source integrity checked on
the Ubuntu test host; the Arch package build itself must run on Arch. The compositor
change was compiled and tested separately as described below. To revert the local
package, `sudo pacman -S niri` restores the repository version; then log out/in.

Official recipe:
https://gitlab.archlinux.org/archlinux/packaging/packages/niri/-/blob/26.04-1/PKGBUILD

Reproduction instructions and measured results are in
[`tests/zen-layout/README.md`](../../../tests/zen-layout/README.md).
This patch has been tested with real nested Wayland clients, but is not an
upstream-approved niri change and still needs hardware/multi-output validation.
