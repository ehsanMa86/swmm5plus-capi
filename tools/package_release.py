#!/usr/bin/env python3
# swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
# https://github.com/ehsanMa86/swmm5plus-capi
#
# File:    tools/package_release.py
# Purpose: Packages a built swmm5plus-capi for download: libraries, bundled Fortran runtime, licenses and a checksummed manifest.
#
# Copyright (C) 2026 Ehsan Madadi
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later
"""Create the release assets that Mirab downloads with "Install SWMM5+".

Usage:
    python3 tools/package_release.py --build build --out dist --version 0.1.0

The script installs the build into a staging folder, copies the Fortran
runtime libraries the solver needs next to the two engine libraries, makes
them load from their own folder ($ORIGIN or @loader_path), and writes the
files below. On Windows the runtime is linked statically, and the script
checks that the DLLs depend on system DLLs only.

    dist/swmm5plus-capi-<version>-<platform>-<file>   one asset per file
    dist/swmm5plus-capi-<platform>.json               manifest (stable name)

The manifest name has no version so that
https://github.com/<owner>/swmm5plus-capi/releases/latest/download/<manifest>
always points at the newest release.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ENGINE_ID = "swmm5plus-1.0"
SWMM5PLUS_VERSION = "1.0.3"
API_VERSION = 2


def platform_id() -> str:
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "x86_64": "x86_64", "arm64": "arm64", "aarch64": "arm64"}.get(machine, machine)
    if sys.platform.startswith("linux"):
        return f"linux-{arch}"
    if sys.platform == "darwin":
        return f"macos-{arch}"
    return f"windows-{arch}"


def run(cmd: list[str]) -> str:
    # No standard input: a tool that asks a question (dylibbundler when it cannot
    # find a library) fails at once instead of waiting forever.
    return subprocess.run(cmd, check=True, capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def linux_runtime(libs: list[Path], stage: Path) -> list[Path]:
    """Copy libgfortran and libquadmath next to the engine and point every
    bundled library at $ORIGIN so nothing is looked up on the system."""
    wanted = ("libgfortran.so", "libquadmath.so")
    bundled: list[Path] = []
    for lib in libs:
        for line in run(["ldd", str(lib)]).splitlines():
            m = re.match(r"\s*(\S+)\s+=>\s+(\S+)", line)
            if m and m.group(1).startswith(wanted):
                target = stage / m.group(1)
                if not target.exists():
                    shutil.copy2(Path(m.group(2)).resolve(), target)
                    bundled.append(target)
    # libgfortran itself depends on libquadmath; resolve it from the folder too.
    for lib in libs + bundled:
        run(["patchelf", "--set-rpath", "$ORIGIN", str(lib)])
    return bundled


def macos_runtime(libs: list[Path], stage: Path) -> list[Path]:
    """Use dylibbundler to copy Homebrew's GCC runtime and rewrite install names."""
    before = set(stage.iterdir())
    # Homebrew's libgfortran refers to libquadmath and libgcc_s through @rpath.
    search: list[str] = []
    gcc_lib = Path(run(["brew", "--prefix", "gcc"]).strip()) / "lib" / "gcc" / "current"
    if gcc_lib.is_dir():
        search = ["-s", str(gcc_lib)]
    for lib in libs:
        run(["dylibbundler", "-of", "-b", "-x", str(lib), "-d", str(stage), "-p", "@loader_path/", "-cd", *search])
    bundled = sorted(set(stage.iterdir()) - before)
    for f in libs + bundled:
        f.chmod(f.stat().st_mode | 0o200)  # Homebrew copies are read-only
        run(["codesign", "--force", "--sign", "-", str(f)])
    # Nothing may still load from the build machine's Homebrew or /usr/local.
    for f in libs + bundled:
        deps = [line.split()[0] for line in run(["otool", "-L", str(f)]).splitlines()[1:] if line.strip()]
        bad = [d for d in deps if d.startswith(("/opt/homebrew", "/usr/local"))]
        if bad:
            raise SystemExit(f"{f.name} still depends on {', '.join(bad)}")
    return bundled


def windows_runtime(libs: list[Path], stage: Path) -> list[Path]:
    """The MinGW build links the GCC and Fortran runtimes statically (see
    CMakeLists.txt). Check that the DLLs depend on Windows system DLLs only,
    because a separate libgcc_s_seh-1.dll or libwinpthread-1.dll could clash
    with the copies a host application has already loaded."""
    runtime = re.compile(r"^(libgfortran|libgcc_s|libwinpthread|libquadmath|libstdc\+\+|libhdf5|libgomp)", re.I)
    for lib in libs:
        imports = re.findall(r"DLL Name:\s*(\S+)", run(["objdump", "-p", str(lib)]))
        bad = [d for d in imports if runtime.match(d)]
        if bad:
            raise SystemExit(f"{lib.name} depends on {', '.join(bad)}; link the runtime statically")
        print(f"{lib.name} imports: {', '.join(sorted(set(imports)))}")
    return []


def gcc_version(build: Path) -> str | None:
    """Version of the GNU Fortran compiler of the build, whose runtime is bundled."""
    cache = (build / "CMakeCache.txt").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^CMAKE_Fortran_COMPILER:\w+=(.+)$", cache, re.M)
    if not m:
        return None
    fc = m.group(1).strip()
    try:
        if "GNU Fortran" not in run([fc, "--version"]):
            return None
        return run([fc, "-dumpfullversion"]).strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def runtime_source(plat: str, gcc: str) -> str:
    """Where the source code of the bundled GNU Fortran runtime is published,
    as the LGPL-2.1 of libquadmath requires."""
    major = gcc.split(".")[0]
    who, url = {
        "linux": ("Ubuntu (package gcc-" + major + ")", "https://launchpad.net/ubuntu/+source/gcc-" + major),
        "macos": ("Homebrew (formula gcc)", "https://github.com/Homebrew/homebrew-core/blob/master/Formula/g/gcc.rb"),
        "windows": ("MSYS2 (package mingw-w64-gcc)", "https://github.com/msys2/MINGW-packages/tree/master/mingw-w64-gcc"),
    }[plat.split("-")[0]]
    if plat.startswith("windows"):
        relink = ("On Windows the runtime is linked statically into the two DLLs. To use a modified\n"
                  "libquadmath, rebuild them from the swmm5plus-capi source with your own GCC.")
    else:
        relink = ("The runtime libraries are separate files next to the engine libraries and can be\n"
                  "replaced with other builds of the same GCC version.")
    return f"""The GNU Fortran runtime in these libraries comes from GCC {gcc}, as built by {who}.

libquadmath is licensed under the GNU Lesser General Public License, version 2.1
(LGPL-2.1.txt). libgfortran and libgcc are licensed under the GNU General Public
License, version 3, with the GCC Runtime Library Exception
(GCC-RUNTIME-LIBRARY-EXCEPTION-3.1.txt).

Source code:
  GCC {gcc}: https://ftp.gnu.org/gnu/gcc/gcc-{gcc}/
  Changes made by {who}: {url}
  swmm5plus-capi: https://github.com/ehsanMa86/swmm5plus-capi

{relink}
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--build", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--version", required=True)
    args = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    plat = platform_id()
    windows = plat.startswith("windows")
    ext = ".dll" if windows else ".dylib" if plat.startswith("macos") else ".so"
    lib_prefix = "" if windows else "lib"

    with tempfile.TemporaryDirectory() as tmp:
        prefix = Path(tmp) / "prefix"
        subprocess.run(["cmake", "--install", str(args.build), "--prefix", str(prefix)], check=True)
        stage = Path(tmp) / "stage"
        stage.mkdir()
        libs = []
        for stem in (lib_prefix + "swmm5plus_capi", lib_prefix + "swmm5plus_swmmc"):
            found = list(prefix.rglob(stem + ext))
            if not found:
                print(f"{stem}{ext} not found in the install tree", file=sys.stderr)
                return 1
            target = stage / (stem + ext)
            shutil.copy2(found[0].resolve(), target)
            libs.append(target)
        if windows:
            bundled = windows_runtime(libs, stage)
        elif plat.startswith("macos"):
            bundled = macos_runtime(libs, stage)
        else:
            bundled = linux_runtime(libs, stage)
        shutil.copy2(root / "LICENSE", stage / "swmm5plus-capi-LICENSE.txt")
        shutil.copy2(root / "THIRD_PARTY_NOTICES.md", stage / "swmm5plus-capi-THIRD_PARTY_NOTICES.md")
        # License texts of the code compiled into the libraries or shipped with them.
        for text in sorted((root / "third_party" / "licenses").glob("*.txt")):
            shutil.copy2(text, stage / text.name)
        gcc = gcc_version(args.build)
        if gcc:
            (stage / "GCC-RUNTIME-SOURCE.txt").write_text(runtime_source(plat, gcc), encoding="utf-8")

        args.out.mkdir(parents=True, exist_ok=True)
        files = []
        for f in sorted(stage.iterdir()):
            asset = f"swmm5plus-capi-{args.version}-{plat}-{f.name}"
            shutil.copy2(f, args.out / asset)
            files.append({"name": f.name, "asset": asset, "size": f.stat().st_size, "sha256": sha256(f)})

    manifest = {
        "format": "mirab-engine/1",
        "engine": ENGINE_ID,
        "name": "SWMM5+",
        "version": SWMM5PLUS_VERSION,
        "package": "swmm5plus-capi",
        "packageVersion": args.version,
        "apiVersion": API_VERSION,
        "platform": plat,
        "homepage": "https://github.com/ehsanMa86/swmm5plus-capi",
        "license": "GPL-3.0-or-later (C interface); SWMM5+ and EPA SWMM are public domain",
        "files": files,
    }
    out = args.out / f"swmm5plus-capi-{plat}.json"
    out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out} with {len(files)} file(s); bundled runtime: {[p.name for p in bundled]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
