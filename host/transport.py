"""Synchronous, fail-closed serial transport with auditable per-attempt logs."""
import json
import platform
import time
from .protocol import Frame, Kind, ProtocolError, Reply, State, Status, StreamDecoder


class DecisionTimeout(TimeoutError):
    pass


def open_serial(port, timeout=.01):
    try:
        import serial
    except ImportError as exc:
        raise RuntimeError("Install host/requirements.txt for physical UART access") from exc
    return serial.Serial(port, baudrate=115200, bytesize=8, parity="N", stopbits=1,
                         timeout=timeout, write_timeout=1, xonxoff=False,
                         rtscts=False, dsrdtr=False)


class Transport:
    def __init__(self, serial, *, deadline=1.0, retries=2, log=None,
                 clock=time.monotonic, sleep=time.sleep):
        if deadline <= 0 or retries < 0:
            raise ValueError("positive deadline and nonnegative retries required")
        self.serial, self.deadline, self.retries = serial, deadline, retries
        self.log, self.clock, self.sleep = log, clock, sleep
        self.round_id = None
        self.last_snapshot = 0
        self.initial_health = None
        self.used_rounds = set()
        self.emit(event="configuration", os=platform.platform(), python=platform.python_version(),
                  port=str(getattr(serial, "port", "test")), baud=115200, data_bits=8,
                  parity="N", stop_bits=1, flow_control=False,
                  deadline_s=deadline, max_retries=retries)

    def emit(self, **event):
        if self.log:
            self.log.write(json.dumps(event, sort_keys=True) + "\n")
            self.log.flush()

    def exchange(self, request, snapshot=None, payload_serialization_s=0):
        encoded_at = self.clock()
        request.validate_request()
        raw = request.encode()
        encode_s = payload_serialization_s + self.clock() - encoded_at
        for attempt in range(self.retries + 1):
            if attempt:
                self.sleep(.110)  # board abandons partial requests before identical retry
            self.serial.reset_input_buffer()
            parser = StreamDecoder()
            begin = self.clock()
            self.emit(event="tx", attempt=attempt, round_id=request.round_id,
                      snapshot_id=request.snapshot_id, hex=raw.hex(), bytes=len(raw),
                      serialization_s=encode_s)
            try:
                written = self.serial.write(raw)
                if written != len(raw):
                    raise OSError("short serial write")
                self.serial.flush()
                while self.clock() - begin < self.deadline:
                    chunk = self.serial.read(512)
                    if chunk:
                        self.emit(event="rx", attempt=attempt, hex=chunk.hex(), bytes=len(chunk))
                    if self.clock() - begin >= self.deadline:
                        break
                    for response in parser.feed(chunk, now=self.clock()):
                        if (response.kind, response.round_id, response.snapshot_id) != (
                                Kind.RESULT, request.round_id, request.snapshot_id):
                            self.emit(event="unmatched_reply", hex=response.encode().hex())
                            continue
                        reply = Reply.decode(response.payload)
                        if reply.status != Status.OK:
                            raise ProtocolError(f"FPGA status {reply.status.name}")
                        if snapshot is not None:
                            reply.validate(snapshot)
                        elif reply.commands or reply.cycles or reply.state != State.HOLD:
                            raise ProtocolError("invalid START acknowledgement")
                        elapsed = self.clock() - begin
                        self.emit(event="decision", attempt=attempt, valid=True,
                                  latency_sample=attempt == 0, round_trip_s=elapsed,
                                  request_bytes=len(raw), reply_bytes=len(response.encode()),
                                  theoretical_line_s=(len(raw) + len(response.encode())) * 10 / 115200,
                                  compute_cycles=reply.cycles, compute_s=reply.cycles / 50_000_000,
                                  parser_errors=parser.errors)
                        return reply
            except Exception as exc:
                self.emit(event="failure", attempt=attempt, valid=False,
                          error=type(exc).__name__, detail=str(exc))
                raise  # explicit device/protocol failures never become software decisions
            self.emit(event="timeout", attempt=attempt, valid=False,
                      elapsed_s=self.clock() - begin, parser_errors=parser.errors)
        raise DecisionTimeout("no valid matching FPGA reply; abort this run")

    def start(self, round_id):
        if round_id in self.used_rounds:
            raise ProtocolError("round ID reuse")
        self.round_id = None
        self.used_rounds.add(round_id)
        self.exchange(Frame(Kind.START, round_id, 0))
        self.round_id, self.last_snapshot, self.initial_health = round_id, 0, None

    def decide(self, snapshot, snapshot_id):
        if self.round_id is None or snapshot_id <= self.last_snapshot:
            raise ProtocolError("START required and snapshot IDs must increase")
        if self.initial_health is not None and snapshot.initial_health != self.initial_health:
            raise ProtocolError("initial health changed within round")
        self.initial_health = snapshot.initial_health
        encoded_at = self.clock()
        payload = snapshot.encode()
        payload_serialization_s = self.clock() - encoded_at
        try:
            reply = self.exchange(Frame(Kind.SNAPSHOT, self.round_id, snapshot_id, payload),
                                  snapshot, payload_serialization_s)
        except Exception:
            self.round_id = None  # abort; caller cannot advance the game on an uncertain decision
            raise
        self.last_snapshot = snapshot_id
        return reply
