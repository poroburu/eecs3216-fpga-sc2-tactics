"""Run the visible Windows SC2 client while the host runs in WSL.

burnysc2 7.3.0 can start the Windows client from WSL, but its launcher joins arguments with
spaces and passes Linux paths ("-dataDir /mnt/c/Program Files (x86)/..."), so the client did
not come up reliably here. This module swaps in a small SC2Process subclass that starts
SC2_x64.exe through PowerShell with properly quoted Windows arguments on a fixed local port,
connects burnysc2's websocket to it, and stops exactly that process afterwards.
Requires WSL networking that can reach Windows' 127.0.0.1 (networkingMode=mirrored here).
"""
from __future__ import annotations
import subprocess
from pathlib import Path

import sc2.main
from sc2.sc2process import SC2Process

SC2_DIR = r"C:\Program Files (x86)\StarCraft II"
PORT = 5555


def _latest_exe() -> str:
    versions = Path("/mnt/c/Program Files (x86)/StarCraft II/Versions")
    base = sorted(p.name for p in versions.iterdir() if p.name.startswith("Base"))[-1]
    return rf"{SC2_DIR}\Versions\{base}\SC2_x64.exe"


def _ps(cmd: str) -> str:
    return subprocess.run(["powershell.exe", "-NoProfile", "-Command", cmd], capture_output=True, text=True).stdout


class _Running:
    """Placeholder for burnysc2's Popen handle (it only checks that one exists)."""


class WindowsSC2Process(SC2Process):
    def _launch(self):
        self._host, self._serverhost, self._port = "127.0.0.1", "127.0.0.1", PORT
        args = ["-listen", "127.0.0.1", "-port", str(PORT), "-displayMode", "0",
                "-windowwidth", "1280", "-windowheight", "800", "-windowx", "40", "-windowy", "40"]
        arglist = ", ".join(f'"{a}"' for a in args)
        out = _ps(f'$p = Start-Process -PassThru -WorkingDirectory "{SC2_DIR}\\Support64" '
                  f'-FilePath "{_latest_exe()}" -ArgumentList @({arglist}); Write-Output $p.Id')
        self._win_pid = int(out.split()[-1])
        return _Running()

    def _clean(self, verbose: bool = True) -> None:
        pid = getattr(self, "_win_pid", None)
        if pid:
            _ps(f"Stop-Process -Id {pid} -Force -ErrorAction SilentlyContinue")
            self._win_pid = None
        self._process = None
        self._ws = None


def install():
    """Make burnysc2's run_game() use the visible Windows client."""
    _ps("Get-Process SC2_x64 -ErrorAction SilentlyContinue | Stop-Process -Force")   # one client at a time
    sc2.main.SC2Process = WindowsSC2Process
