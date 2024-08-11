import os
import pathlib
import re
import shutil
from collections import deque
from itertools import chain

import magic
from elftools.elf.elffile import ELFFile

# https://github.com/pypa/auditwheel/blob/main/src/auditwheel/lddtree.py
# https://github.com/eliben/pyelftools/blob/main/elftools/elf/dynamic.py

SYSROOT = pathlib.Path(os.environ["SYSROOT_DIR"])
TABULAROOT = SYSROOT / os.environ["INSTALL_PREFIX"].lstrip("/")
LIB_DIRS = [
    SYSROOT / "lib",
    SYSROOT / "usr" / "lib",
    TABULAROOT / "lib",
]

SEED_PATHS = [
    TABULAROOT / "bin" / "python3",
    TABULAROOT / "bin" / "python3.11",
    TABULAROOT / "lib" / "python3.11",
    TABULAROOT / "bin" / "fbink",
    TABULAROOT / "lib" / "libevdev.so",
    TABULAROOT / "bin" / "libevdev-events",
    TABULAROOT / "bin" / "libevdev-list-codes",
    TABULAROOT / "share" / "terminfo",
    # TABULAROOT / "lib" / "terminfo",  # symlink to share/terminfo
    TABULAROOT / "bin" / "py-spy",
    TABULAROOT / "modules" / "uhid.ko",
]

SCRIPTS_WITH_HASHBANGS = [
    TABULAROOT / "bin" / "tabula",
    TABULAROOT / "bin" / "list-tabula-fonts",
    TABULAROOT / "bin" / "print-kobo-events",
    TABULAROOT / "bin" / "timeflake",
]

# TODO: take this as an argument, maybe?
DESTROOT = pathlib.Path(pathlib.Path("output").resolve())

ELF_MAGIC = re.compile(r"ELF ((32)|(64))-bit (L|M)SB +(executable|pie executable|shared object)")

# magic.from_file(pathlib.Path("tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula/lib/libfbink.so.1.25.0"))
# "ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, with debug_info, not stripped"

# elf = ELFFile(pathlib.Path("tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula/lib/libfbink.so.1").open("rb"))
# # dynamic = {s.header.p_type: s for s in elf.iter_segments()}['PT_DYNAMIC']
# [t.needed for t in elf.get_section_by_name(".dynamic").iter_tags() if t["d_tag"] == "DT_NEEDED"]
# [t.soname for t in elf.get_section_by_name(".dynamic").iter_tags() if t["d_tag"] == "DT_SONAME"]


class Process:
    def __init__(self, sysroot: pathlib.Path, lib_dirs: list[pathlib.Path], seed: list[pathlib.Path], scripts: list[pathlib.Path]):
        self.sysroot = sysroot
        self.lib_dirs = lib_dirs
        self.scripts = scripts
        # dirs is a list because we only need to do one pass.
        self.dirs_to_check: list[pathlib.Path] = []
        self.files_to_check: deque[pathlib.Path] = deque()
        self.symlinks_to_check: deque[pathlib.Path] = deque()
        self.elve_status: dict[pathlib.Path, bool] = {}

        self.will_copy: set[pathlib.Path] = set()
        self.dirs_to_copy: deque[pathlib.Path] = deque()
        self.files_to_copy: deque[pathlib.Path] = deque()
        self.symlinks_to_copy: deque[pathlib.Path] = deque()

        for path in seed + scripts:
            self.add_path_to_check(path)

    def add_path_to_check(self, path: pathlib.Path):
        path.resolve(strict=True)  # check it exists
        if not path.is_relative_to(self.sysroot):
            raise ValueError(f"{path} is not contained in sysroot {self.sysroot}")
        if path in self.will_copy:
            return
        if not path.is_symlink():
            if path.is_dir():
                self.dirs_to_check.append(path)
            else:
                self.files_to_check.append(path)
            return
        final_target = path.resolve()
        if final_target.is_dir():
            self.dirs_to_check.append(final_target)
            self.symlinks_to_check.append(path)
        # symlink to a file. resolve one level of indirection.
        immediate_target = path.parent / path.readlink()
        self.add_path_to_check(immediate_target)
        self.symlinks_to_check.append(path)

    def elfdepnames(self, path: pathlib.Path) -> list[str]:
        elf = ELFFile(path.open("rb"))
        dynamic = elf.get_section_by_name(".dynamic")
        if dynamic is None:
            return []
        needed = [t.needed for t in dynamic.iter_tags() if t["d_tag"] == "DT_NEEDED"]
        # not strictly speaking a dep, but a potential name to copy
        soname = [t.soname for t in dynamic.iter_tags() if t["d_tag"] == "DT_SONAME"]
        return needed + soname

    def add_elf_deps_to_check(self, path: pathlib.Path):
        # assume the path exists and we've already verified it's an ELF via magic
        for depname in self.elfdepnames(path):
            for candidate in chain.from_iterable(libdir.rglob(depname) for libdir in LIB_DIRS):
                self.add_path_to_check(candidate)

    def already_will_copy(self, path: pathlib.Path):
        return path in self.will_copy or any(parent for parent in path.parents if parent in self.will_copy)

    def do_check(self):
        # ELF scanning won't add any extra dirs, so we can do just one pass on that.
        if self.dirs_to_check:
            self.dirs_to_check.sort()
            for path in self.dirs_to_check:
                if self.already_will_copy(path):
                    continue
                # find elve files within
                for root, _dirs, files in path.walk():
                    for filename in files:
                        filepath = root / filename
                        filemagic = magic.from_file(filepath)
                        if ELF_MAGIC.match(filemagic):
                            self.elve_status[filepath] = True
                            self.add_path_to_check(filepath)
                        else:
                            self.elve_status[filepath] = False
                self.will_copy.add(path)
                self.dirs_to_copy.append(path)
            self.dirs_to_check = []
        while self.files_to_check or self.symlinks_to_check:
            while self.files_to_check:
                filepath = self.files_to_check.popleft()
                if filepath in self.will_copy:
                    continue
                if filepath not in self.elve_status:
                    filemagic = magic.from_file(filepath)
                    self.elve_status[filepath] = bool(ELF_MAGIC.match(filemagic))
                if self.elve_status[filepath]:
                    self.add_elf_deps_to_check(filepath)
                if not self.already_will_copy(filepath):
                    self.files_to_copy.append(filepath)
                self.adjust_hashbang(filepath)
                self.will_copy.add(filepath)
            while self.symlinks_to_check:
                sympath = self.symlinks_to_check.popleft()
                if not self.already_will_copy(sympath):
                    self.symlinks_to_copy.append(sympath)
                self.will_copy.add(sympath)

    def do_copy(self, destroot: pathlib.Path):
        while self.dirs_to_copy:
            srcdirpath = self.dirs_to_copy.popleft()
            destdirpath = destroot / (srcdirpath.relative_to(self.sysroot))
            print(f"Copying dir {srcdirpath} to {destdirpath}")
            shutil.copytree(srcdirpath, destdirpath, symlinks=True)
        while self.files_to_copy:
            srcfilepath = self.files_to_copy.popleft()
            destfilepath = destroot / (srcfilepath.relative_to(self.sysroot))
            print(f"Copying file {srcfilepath} to {destfilepath}")
            destfilepath.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(srcfilepath, destfilepath, follow_symlinks=False)
        while self.symlinks_to_copy:
            srcsympath = self.symlinks_to_copy.popleft()
            destsympath = destroot / (srcsympath.relative_to(self.sysroot))
            print(f"Copying symlink {srcsympath} to {destsympath}")
            destsympath.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(srcsympath, destsympath, follow_symlinks=False)

    def adjust_hashbang(self, filepath: pathlib.Path):
        fullmagic = magic.Magic(keep_going=True).from_file(filepath)
        if "text executable" not in fullmagic:
            return
        if str(self.sysroot) not in fullmagic:
            return
        lines = filepath.read_text().splitlines(keepends=True)
        lines[0] = lines[0].replace(str(self.sysroot), "")
        with filepath.open("wt") as outfile:
            outfile.writelines(lines)


if __name__ == "__main__":
    p = Process(SYSROOT, LIB_DIRS, SEED_PATHS, SCRIPTS_WITH_HASHBANGS)
    p.do_check()
    DESTROOT.mkdir(parents=True)
    p.do_copy(DESTROOT)
