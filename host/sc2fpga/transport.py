"""Ways for the host to reach a target-selection engine.

  win:COM5      Windows COM port through host/bridge/com_bridge.ps1 (for WSL; no usbipd needed)
  /dev/ttyUSB0  native serial port via pyserial (Linux, or WSL after `usbipd attach`)
  COM5          native serial port via pyserial on Windows
  model         the Python reference pretending to be the FPGA (no hardware)
"""
from __future__ import annotations
import subprocess, time
from pathlib import Path
from .protocol import Reply, decode_reply, encode_reply, reply_length, RSP_SYNC, Snapshot, encode_request
from .reference import expected_reply


class LinkError(RuntimeError):
    pass


class Transport:
    def transact(self, request: bytes) -> bytes:
        raise NotImplementedError

    def flush(self):
        pass

    def close(self):
        pass

    def query(self, snap: Snapshot) -> tuple[Reply, float]:
        t = time.perf_counter()
        raw = self.transact(encode_request(snap))
        return decode_reply(raw), time.perf_counter() - t


class PowerShellBridge(Transport):
    def __init__(self, port: str, timeout_ms: int = 500):
        script = Path(__file__).resolve().parent.parent / "bridge" / "com_bridge.ps1"
        win = subprocess.check_output(["wslpath", "-w", str(script)], text=True).strip()
        self.p = subprocess.Popen(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", win,
                                   "-Port", port, "-TimeoutMs", str(timeout_ms)],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        hello = self.p.stdout.readline().strip()
        if not hello.startswith("READY"):
            raise LinkError(f"bridge failed to open {port}: {hello!r}")

    def transact(self, request: bytes) -> bytes:
        self.p.stdin.write(f"X {request.hex()}\n"); self.p.stdin.flush()
        kind, _, data = self.p.stdout.readline().strip().partition(" ")
        if kind != "R":
            raise LinkError(f"no complete reply (got {data or 'nothing'})")
        return bytes.fromhex(data)

    def flush(self):
        time.sleep(0.03)
        self.p.stdin.write("F\n"); self.p.stdin.flush(); self.p.stdout.readline()

    def close(self):
        try:
            self.p.stdin.write("Q\n"); self.p.stdin.flush(); self.p.wait(3)
        except Exception:
            self.p.kill()


class PySerial(Transport):
    def __init__(self, port: str, timeout: float = 0.5):
        import serial
        self.s = serial.Serial(port, 115200, timeout=timeout)

    def transact(self, request: bytes) -> bytes:
        self.s.write(request)
        while True:
            b = self.s.read(1)
            if not b:
                raise LinkError("timeout waiting for reply")
            if b[0] == RSP_SYNC:
                break
        head = self.s.read(4)
        rest = self.s.read(head[3] + 3) if len(head) == 4 else b""
        raw = b + head + rest
        if len(head) != 4 or len(raw) != reply_length(head[3]):
            raise LinkError(f"short reply {raw.hex()}")
        return raw

    def flush(self):
        time.sleep(0.03); self.s.reset_input_buffer()

    def close(self):
        self.s.close()


class Model(Transport):
    """Software stand-in for the board (policy fixed at construction, like SW0)."""
    def __init__(self, policy: int = 1):
        self.policy = policy

    def transact(self, request: bytes) -> bytes:
        from .reference import reply_for_bytes
        return encode_reply(reply_for_bytes(request, self.policy))


def open_transport(spec: str, policy: int = 1) -> Transport:
    if spec == "model":
        return Model(policy)
    if spec.startswith("win:"):
        return PowerShellBridge(spec[4:])
    return PySerial(spec)
