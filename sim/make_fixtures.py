"""Independent fixture authoring, intentionally does not import host.protocol.

Run only when reviewing a contract revision. Tests use committed fixture bytes.
"""
import json
from pathlib import Path


def le(value, width):
    return [(value >> (8*i)) & 255 for i in range(width)]


def envelope(kind, rid, sid, payload, version=1):
    b = [version, kind] + le(rid, 4) + le(sid, 4) + le(len(payload), 2) + payload
    return bytes([165, 90] + b + [(-sum(b)) & 255])


def record(index, ready, x, y, hp, maximum, damage, reach):
    return [index, ready] + sum((le(v, 2) for v in (x, y, hp, maximum, damage, reach)), [])


def snapshot(friends, enemies, initial, points=(640, 640, 0, 0)):
    return [len(friends), len(enemies)] + le(initial, 4) + sum((le(v, 2) for v in points), []) + sum(friends+enemies, [])


def fixtures():
    cases = []
    def add(name, raw, envelope_ok=True, request_ok=True):
        cases.append(dict(name=name, hex=raw.hex(), envelope_ok=envelope_ok,
                          request_ok=request_ok, bytes=len(raw)))
    add("start", envelope(1, 1, 0, []))
    add("round_reset", envelope(1, 2, 0, []))
    empty = envelope(2, 1, 1, snapshot([], [], 0))
    add("empty", empty)
    one = snapshot([record(0, 1, 64, 128, 720, 720, 96, 384)],
                   [record(3, 0, 256, 128, 560, 560, 80, 96)], 720)
    add("one_each", envelope(2, 1, 2, one))
    full = snapshot([record(i, i%2, 65535, 0, 65535, 65535, 65535, 65535) for i in range(16)],
                    [record(i, 0, 0, 65535, 1, 65535, 1, 0) for i in range(16)], 16*65535,
                    (65535, 65535, 0, 0))
    add("maximal", envelope(2, 0xffffffff, 0xffffffff, full))
    add("start_ack", envelope(129, 1, 0, [0]*8), request_ok=False)
    result = [0, 2, 1, 0] + le(1234, 4) + [0, 1, 3, 0, 0, 0, 0, 0]
    add("attack_reply", envelope(129, 1, 2, result), request_ok=False)
    add("not_started", envelope(129, 1, 1, [1]+[0]*7), request_ok=False)
    add("bad_checksum", empty[:-1]+bytes([empty[-1]^1]), False, False)
    add("bad_version", envelope(2, 1, 1, list(empty[14:-1]), version=2), False, False)
    add("unsupported_type", envelope(3, 1, 1, []), False, False)
    add("zero_round", envelope(1, 0, 0, []), False, False)
    add("oversize", envelope(2, 1, 1, [0]*463), False, False)
    add("truncated", empty[:-3], False, False)
    add("bad_count", envelope(2, 1, 1, [17]+list(empty[15:-1])), request_ok=False)
    invalid = one.copy(); invalid[14+6:14+8] = [0, 0]
    add("zero_health", envelope(2, 1, 1, invalid), request_ok=False)
    invalid = one.copy(); invalid[14+14+1] = 1
    add("enemy_ready", envelope(2, 1, 1, invalid), request_ok=False)
    invalid = one.copy(); invalid[2:6] = le(719, 4)
    add("initial_too_small", envelope(2, 1, 1, invalid), request_ok=False)
    add("duplicate_index", envelope(2, 1, 1, snapshot([
        record(0, 1, 0, 0, 1, 1, 1, 0), record(0, 1, 0, 0, 1, 1, 1, 0)], [], 2)), request_ok=False)
    add("start_with_payload", envelope(1, 1, 0, [0]), request_ok=False)
    add("snapshot_zero", envelope(2, 1, 0, list(empty[14:-1])), request_ok=False)
    return cases


if __name__ == "__main__":
    root = Path(__file__).parent / "fixtures"
    root.mkdir(exist_ok=True)
    (root / "protocol.json").write_text(json.dumps(fixtures(), indent=2)+"\n")
