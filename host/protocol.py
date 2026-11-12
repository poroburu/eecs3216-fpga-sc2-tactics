"""Protocol v1. See docs/protocol.md; no serial or SC2 dependency."""
from dataclasses import dataclass
from enum import IntEnum
import math
import struct
import time

SYNC = b"\xa5\x5a"
VERSION = 1
MAX_PAYLOAD = 462
HEADER = struct.Struct("<BBIIH")
UNIT = struct.Struct("<BB6H")
PREFIX = struct.Struct("<BBI4H")
COMMAND = struct.Struct("<BBBBHH")
RESULT = struct.Struct("<BBBBI")
MAX_INITIAL_HEALTH = 16 * 65535


class Kind(IntEnum):
    START = 1
    SNAPSHOT = 2
    RESULT = 0x81


class Status(IntEnum):
    OK = 0
    NOT_STARTED = 1
    STALE = 2
    CONFLICT = 3
    BUSY = 4
    INVALID = 5
    UNSUPPORTED = 6


class Intent(IntEnum):
    HOLD = 0
    ATTACK = 1
    MOVE = 2


class State(IntEnum):
    HOLD = 0
    ADVANCE = 1
    ATTACK = 2
    RETREAT = 3


class ProtocolError(ValueError):
    pass


def uint(value, bits, name):
    if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value < 1 << bits:
        raise ProtocolError(f"{name} must be an unsigned {bits}-bit integer")
    return value


def fixed(value, fractional_bits):
    """Nonnegative finite value -> uint16, round half up, reject overflow."""
    if not math.isfinite(value) or value < 0:
        raise ProtocolError("fixed-point value must be finite and nonnegative")
    return uint(math.floor(value * (1 << fractional_bits) + 0.5), 16, "fixed-point")


@dataclass(frozen=True)
class Frame:
    kind: int
    round_id: int
    snapshot_id: int
    payload: bytes = b""

    def validate_request(self):
        if self.kind == Kind.START:
            if self.snapshot_id or self.payload:
                raise ProtocolError("START must have snapshot ID zero and empty payload")
        elif self.kind == Kind.SNAPSHOT:
            if not self.snapshot_id:
                raise ProtocolError("SNAPSHOT ID must be positive")
            Snapshot.decode(self.payload)
        else:
            raise ProtocolError("expected a request")

    def encode(self):
        uint(self.kind, 8, "kind")
        uint(self.round_id, 32, "round ID")
        uint(self.snapshot_id, 32, "snapshot ID")
        if self.kind not in Kind._value2member_map_ or not self.round_id:
            raise ProtocolError("unsupported kind or zero round ID")
        if len(self.payload) > MAX_PAYLOAD:
            raise ProtocolError("oversize payload")
        body = HEADER.pack(VERSION, self.kind, self.round_id,
                           self.snapshot_id, len(self.payload)) + self.payload
        return SYNC + body + bytes([-sum(body) & 255])


def decode(raw):
    if len(raw) < 15 or raw[:2] != SYNC:
        raise ProtocolError("bad sync or truncated frame")
    version, kind, rid, sid, length = HEADER.unpack(raw[2:14])
    if version != VERSION or kind not in Kind._value2member_map_:
        raise ProtocolError("unsupported version or message type")
    if length > MAX_PAYLOAD or len(raw) != length + 15:
        raise ProtocolError("invalid frame length")
    if sum(raw[2:]) & 255:
        raise ProtocolError("checksum mismatch")
    if not rid:
        raise ProtocolError("zero round ID")
    return Frame(kind, rid, sid, bytes(raw[14:-1]))


class StreamDecoder:
    """Bounded parser. Bad headers discard one byte; timeouts discard all."""
    def __init__(self):
        self.buffer = bytearray()
        self.last_byte = None
        self.errors = 0

    def feed(self, data, now=None):
        now = time.monotonic() if now is None else now
        if self.buffer and self.last_byte is not None and now - self.last_byte >= .100:
            self.buffer.clear()
            self.errors += 1
        if data:
            self.last_byte = now
        frames = []
        # Process incrementally so even arbitrarily large noise chunks use <=477 bytes.
        for byte in data:
            self.buffer.append(byte)
            while self.buffer:
                if self.buffer[0] != 0xa5:
                    del self.buffer[0]
                elif len(self.buffer) == 1:
                    break
                elif self.buffer[1] != 0x5a:
                    del self.buffer[0]
                elif len(self.buffer) < 14:
                    break
                else:
                    size = int.from_bytes(self.buffer[12:14], "little") + 15
                    if self.buffer[2] != VERSION or self.buffer[3] not in Kind._value2member_map_ or size > 477:
                        self.errors += 1
                        del self.buffer[0]
                        continue
                    if len(self.buffer) < size:
                        break
                    try:
                        frames.append(decode(self.buffer[:size]))
                        del self.buffer[:size]
                    except ProtocolError:
                        self.errors += 1
                        del self.buffer[0]
        return frames


@dataclass(frozen=True)
class Unit:
    index: int
    ready: int
    x: int
    y: int
    health: int
    max_health: int
    damage: int
    reach: int
    # Record is 14 bytes: index, ready, six uint16 fields.

    def encode(self, enemy=False):
        values = (self.x, self.y, self.health, self.max_health, self.damage, self.reach)
        if not 0 <= uint(self.index, 8, "unit index") < 16:
            raise ProtocolError("unit index out of range")
        if type(self.ready) is not int or self.ready not in (0, 1) or enemy and self.ready:
            raise ProtocolError("invalid ready flag")
        for v in values:
            uint(v, 16, "unit field")
        if not 0 < self.health <= self.max_health or not self.damage:
            raise ProtocolError("health/max-health/damage invalid")
        return struct.pack("<BB6H", self.index, self.ready, *values)


@dataclass(frozen=True)
class Snapshot:
    friends: tuple[Unit, ...]
    enemies: tuple[Unit, ...]
    initial_health: int
    objective: tuple[int, int]
    safety: tuple[int, int]

    def encode(self):
        if len(self.friends) > 16 or len(self.enemies) > 16:
            raise ProtocolError("more than 16 units per side")
        uint(self.initial_health, 32, "initial health")
        if not sum(u.max_health for u in self.friends) <= self.initial_health <= MAX_INITIAL_HEALTH:
            raise ProtocolError("initial health must include every current friendly")
        points = (*self.objective, *self.safety)
        if len(points) != 4:
            raise ProtocolError("two 2D waypoints required")
        for v in points:
            uint(v, 16, "waypoint")
        payload = PREFIX.pack(len(self.friends), len(self.enemies), self.initial_health, *points)
        for side, enemy in ((self.friends, False), (self.enemies, True)):
            previous = -1
            for u in side:
                if u.index <= previous:
                    raise ProtocolError("indices must be strictly increasing per side")
                previous = u.index
                payload += u.encode(enemy)
        return payload

    @classmethod
    def decode(cls, payload):
        if len(payload) < PREFIX.size:
            raise ProtocolError("truncated snapshot prefix")
        nf, ne, initial, ox, oy, sx, sy = PREFIX.unpack(payload[:PREFIX.size])
        if nf > 16 or ne > 16 or len(payload) != 14 + (nf + ne) * 14:
            raise ProtocolError("invalid counts/length")
        units = tuple(Unit(*v) for v in struct.iter_unpack("<BB6H", payload[14:]))
        result = cls(units[:nf], units[nf:], initial, (ox, oy), (sx, sy))
        result.encode()  # shared semantic constraints also apply to wire input
        return result


@dataclass(frozen=True)
class Command:
    actor: int
    intent: Intent
    target: int = 255
    x: int = 0
    y: int = 0


@dataclass(frozen=True)
class Reply:
    status: Status
    state: State
    cycles: int
    commands: tuple[Command, ...] = ()

    @classmethod
    def decode(cls, payload):
        if len(payload) < 8:
            raise ProtocolError("truncated reply")
        status, state, count, reserved, cycles = RESULT.unpack(payload[:8])
        if status not in Status._value2member_map_ or state not in State._value2member_map_:
            raise ProtocolError("unknown reply status/state")
        if reserved or count > 16 or len(payload) != 8 + count * 8:
            raise ProtocolError("invalid reply length/reserved field")
        commands = []
        for actor, intent, target, reserved, x, y in struct.iter_unpack("<BBBBHH", payload[8:]):
            if actor >= 16 or intent not in Intent._value2member_map_ or reserved:
                raise ProtocolError("invalid command")
            if intent == Intent.ATTACK:
                if target >= 16 or x or y:
                    raise ProtocolError("invalid attack")
            elif target != 255 or intent == Intent.HOLD and (x or y):
                raise ProtocolError("invalid move/hold")
            commands.append(Command(actor, Intent(intent), target, x, y))
        if status and (state or cycles or count):
            raise ProtocolError("error replies must have zero state/cycles/commands")
        return cls(Status(status), State(state), cycles, tuple(commands))

    def validate(self, snapshot):
        if self.status != Status.OK:
            raise ProtocolError(f"FPGA status {self.status.name}")
        if tuple(c.actor for c in self.commands) != tuple(u.index for u in snapshot.friends):
            raise ProtocolError("reply must cover each friendly exactly once in index order")
        enemies = {u.index for u in snapshot.enemies}
        friends = {u.index: u for u in snapshot.friends}
        for c in self.commands:
            if c.intent == Intent.ATTACK and (c.target not in enemies or not friends[c.actor].ready):
                raise ProtocolError("attack target absent or actor on cooldown")
            if c.intent == Intent.MOVE and (c.x, c.y) not in (snapshot.objective, snapshot.safety):
                raise ProtocolError("move to unauthored waypoint")
