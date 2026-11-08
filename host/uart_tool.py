"""Physical UART tools. Run python3 -m host.uart_tool --help."""
import argparse
import json
from pathlib import Path
import platform
import time
from .protocol import Snapshot, Unit
from .transport import Transport, open_serial


def loopback(port):
    """Adapter TXD/RXD loop only, with FPGA disconnected."""
    raw = b"FPGA UART loopback\r\n" + bytes([0, 255, 85, 170]) + bytes(range(256))
    port.reset_input_buffer()
    begin = time.monotonic()
    if port.write(raw) != len(raw):
        raise OSError("short write")
    port.flush()
    received = bytearray()
    while len(received) < len(raw) and time.monotonic() - begin < 2:
        received.extend(port.read(len(raw) - len(received)))
    if received != raw:
        raise RuntimeError(f"loopback mismatch: sent {raw.hex()}, received {received.hex()}")
    return dict(event="adapter_loopback", valid=True, tx_hex=raw.hex(), rx_hex=received.hex(),
                bytes=len(raw), elapsed_s=time.monotonic() - begin)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["loopback", "benchmark"])
    parser.add_argument("--port", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--round-id", type=int, default=1)
    parser.add_argument("--repeat", type=int, default=10)
    parser.add_argument("--driver-version", required=True)
    parser.add_argument("--latency-timer-ms", required=True,
                        help="Measured/configured setting, or 'unknown'; never guessed")
    args = parser.parse_args()
    if args.repeat <= 0:
        parser.error("--repeat must be positive")
    # Exclusive creation prevents overwriting a measurement record.
    with args.log.open("x") as log, open_serial(args.port) as serial:
        log.write(json.dumps(dict(event="environment", os=platform.platform(),
                                 driver_version=args.driver_version,
                                 latency_timer_ms=args.latency_timer_ms,
                                 port=args.port)) + "\n")
        if args.mode == "loopback":
            log.write(json.dumps(loopback(serial)) + "\n")
            print("PASS: text and all 256 binary values echoed exactly")
            return
        transport = Transport(serial, log=log)
        transport.start(args.round_id)
        sid = 0
        # Same initial health throughout this synthetic round; no SC2 inference.
        for count in (0, 4, 8, 16):
            friends = tuple(Unit(i, 1, 64*i, 0, 720, 720, 96, 384) for i in range(count))
            enemies = tuple(Unit(i, 0, 64*i, 64, 560, 560, 80, 96) for i in range(count))
            snapshot = Snapshot(friends, enemies, 16*720, (640, 640), (0, 0))
            for _ in range(args.repeat):
                sid += 1
                transport.decide(snapshot, sid)
        print(f"Recorded {sid} validated synthetic decisions; see {args.log}")


if __name__ == "__main__":
    main()
