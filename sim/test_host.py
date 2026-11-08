import io
import json
from pathlib import Path
import random
import unittest
from host.protocol import (Command, Frame, Intent, Kind, ProtocolError, Reply,
                           Snapshot, State, Status, StreamDecoder, Unit, decode, fixed)
from host.transport import DecisionTimeout, Transport
from host.bridge import ObservedUnit, RoundBridge, single_step

CASES = {c["name"]: c for c in json.loads((Path(__file__).parent / "fixtures/protocol.json").read_text())}


def raw(name):
    return bytes.fromhex(CASES[name]["hex"])


class ProtocolTests(unittest.TestCase):
    def test_committed_wire_fixtures(self):
        for name, case in CASES.items():
            with self.subTest(name=name):
                if not case["envelope_ok"]:
                    with self.assertRaises(ProtocolError): decode(raw(name))
                else:
                    frame = decode(raw(name))
                    self.assertEqual(frame.encode(), raw(name))
                    if case["request_ok"]:
                        frame.validate_request()
                        if frame.kind == Kind.SNAPSHOT:
                            self.assertEqual(Snapshot.decode(frame.payload).encode(), frame.payload)
                    else:
                        with self.assertRaises(ProtocolError): frame.validate_request()

    def test_known_answer_encoder(self):
        snapshot = Snapshot((Unit(0, 1, 64, 128, 720, 720, 96, 384),),
                            (Unit(3, 0, 256, 128, 560, 560, 80, 96),), 720,
                            (640, 640), (0, 0))
        self.assertEqual(Frame(Kind.SNAPSHOT, 1, 2, snapshot.encode()).encode(), raw("one_each"))
        reply = Reply.decode(decode(raw("attack_reply")).payload)
        reply.validate(snapshot)
        self.assertEqual(reply.cycles, 1234)

    def test_chunking_noise_checksum_and_resync(self):
        decoder = StreamDecoder()
        rng = random.Random(3216)
        stream = b"\x00\x5a\xa5" + raw("start") + raw("bad_checksum") + raw("empty")
        frames = []
        now = 0
        while stream:
            size = rng.randrange(1, 10)
            frames.extend(decoder.feed(stream[:size], now=now))
            now += .001
            stream = stream[size:]
        self.assertEqual([f.encode() for f in frames], [raw("start"), raw("empty")])
        self.assertEqual(decoder.errors, 1)

    def test_interbyte_timeout_including_exact_boundary(self):
        parser = StreamDecoder()
        parser.feed(raw("empty")[:20], now=0)
        self.assertEqual(parser.feed(raw("empty"), now=.100), [decode(raw("empty"))])
        self.assertEqual(parser.errors, 1)

    def test_bounded_noise(self):
        parser = StreamDecoder()
        self.assertEqual(parser.feed(b"\xa5"*100_000), [])
        self.assertLessEqual(len(parser.buffer), 477)

    def test_full_capacity_and_fixed_point(self):
        snapshot = Snapshot.decode(decode(raw("maximal")).payload)
        self.assertEqual(len(snapshot.friends), 16)
        self.assertEqual(len(raw("maximal")), 477)
        self.assertEqual(fixed(1/128, 6), 1)
        for v in (-1, float("nan"), float("inf"), 1024):
            with self.assertRaises(ProtocolError): fixed(v, 6)

    def test_invalid_commands_fail_before_use(self):
        snap = Snapshot.decode(decode(raw("one_each")).payload)
        for commands in ((), (Command(0, Intent.ATTACK, 2),),
                         (Command(0, Intent.MOVE, 255, 999, 999),),
                         (Command(0, Intent.HOLD), Command(0, Intent.HOLD))):
            with self.assertRaises(ProtocolError): Reply(Status.OK, State.ATTACK, 1, commands).validate(snap)

    def test_reply_reserved_and_error_fields(self):
        for payload in (bytes([0,0,0,1,0,0,0,0]), bytes([1,0,0,0,1,0,0,0]),
                        bytes([0,0,1,0,0,0,0,0,0,2,0,0,0,0,0,0])):
            with self.assertRaises(ProtocolError): Reply.decode(payload)


class Clock:
    def __init__(self): self.now = 0
    def __call__(self): return self.now
    def sleep(self, seconds): self.now += seconds


class Serial:
    port = "fake"
    def __init__(self, clock, response):
        self.clock, self.response = clock, response
        self.rx = bytearray()
        self.writes = []
    def write(self, data):
        self.writes.append(data)
        self.rx.extend(self.response(decode(data), len(self.writes)))
        return len(data)
    def read(self, size):
        self.clock.sleep(.01)
        result = self.rx[:size]
        del self.rx[:size]
        return bytes(result)
    def flush(self): pass
    def reset_input_buffer(self): self.rx.clear()


def ack(frame):
    return Frame(Kind.RESULT, frame.round_id, frame.snapshot_id, bytes(8)).encode()


class TransportTests(unittest.TestCase):
    def transport(self, response, **kw):
        clock, log = Clock(), io.StringIO()
        serial = Serial(clock, response)
        return Transport(serial, clock=clock, sleep=clock.sleep, log=log, **kw), serial, log

    def test_start_and_empty_decision(self):
        t, serial, log = self.transport(lambda f, _: ack(f))
        t.start(1)
        t.decide(Snapshot((), (), 0, (0,0), (0,0)), 1)
        events = [json.loads(x) for x in log.getvalue().splitlines()]
        self.assertEqual([e["compute_cycles"] for e in events if e["event"] == "decision"], [0,0])
        self.assertEqual(len(serial.writes), 2)

    def test_identical_retry_not_latency_sample(self):
        t, serial, log = self.transport(lambda f, n: b"" if n == 1 else ack(f), deadline=.03)
        t.start(1)
        self.assertEqual(serial.writes[0], serial.writes[1])
        self.assertIn('"latency_sample": false', log.getvalue())

    def test_stale_corrupt_and_truncated_reply(self):
        def response(f, _):
            stale = Frame(Kind.RESULT, f.round_id+1, f.snapshot_id, bytes(8)).encode()
            good = ack(f)
            return stale + good[:-1] + bytes([good[-1]^1]) + good
        t, _, log = self.transport(response)
        t.start(1)
        self.assertIn("unmatched_reply", log.getvalue())
        self.assertIn('"parser_errors": 1', log.getvalue())
        t, _, _ = self.transport(lambda f, n: ack(f)[:-2], deadline=.03, retries=0)
        with self.assertRaises(DecisionTimeout): t.start(1)

    def test_board_reset_fails_and_invalidates_session(self):
        def response(f, _):
            if f.kind == Kind.START: return ack(f)
            return Frame(Kind.RESULT, f.round_id, f.snapshot_id, bytes([1]+[0]*7)).encode()
        t, _, _ = self.transport(response)
        t.start(1)
        with self.assertRaisesRegex(ProtocolError, "NOT_STARTED"):
            t.decide(Snapshot((), (), 0, (0,0), (0,0)), 1)
        self.assertIsNone(t.round_id)

    def test_timeout_bounded_retries(self):
        t, serial, _ = self.transport(lambda f, n: b"", deadline=.02, retries=2)
        with self.assertRaises(DecisionTimeout): t.start(1)
        self.assertEqual(len(serial.writes), 3)

    def test_full_capacity_request(self):
        def response(f, _):
            if f.kind == Kind.START: return ack(f)
            commands = b"".join(bytes([i,0,255,0,0,0,0,0]) for i in range(16))
            return Frame(Kind.RESULT, f.round_id, f.snapshot_id, bytes([0,0,16,0,0,0,0,0])+commands).encode()
        t, serial, _ = self.transport(response)
        t.start(1)
        t.decide(Snapshot.decode(decode(raw("maximal")).payload), 1)
        self.assertEqual(len(serial.writes[-1]), 477)

    def test_initial_health_and_ids_are_stable(self):
        t, _, _ = self.transport(lambda f, n: ack(f))
        t.start(1)
        t.decide(Snapshot((), (), 1, (0,0), (0,0)), 1)
        with self.assertRaises(ProtocolError): t.decide(Snapshot((), (), 2, (0,0), (0,0)), 2)
        with self.assertRaises(ProtocolError): t.start(1)


class BridgeTests(unittest.TestCase):
    def units(self):
        return ObservedUnit(100, 1, 2, 45, 45, 6, 6, True), ObservedUnit(999, 2, 2, 35, 35, 5, 1)

    def test_tag_lifetime_and_holds(self):
        friend, enemy = self.units()
        bridge = RoundBridge([friend], (10,10), (0,0))
        snapshot = bridge.snapshot([friend], [enemy])
        reply = Reply(Status.OK, State.ATTACK, 123, (Command(0, Intent.ATTACK, 0),))
        actions = bridge.actions(snapshot, reply)
        self.assertEqual(actions, [(100, ("attack",999))])
        self.assertEqual(bridge.actions(snapshot, reply), actions)  # not yet confirmed
        bridge.confirm_actions(actions)
        self.assertEqual(bridge.actions(snapshot, reply), [])
        self.assertEqual(bridge.actions(snapshot, reply, current_orders={}), actions)
        empty = bridge.snapshot([], [])
        self.assertEqual(empty.initial_health, 720)
        self.assertEqual(bridge.snapshot([friend], [enemy]).enemies[0].index, 0)
        hold = Reply(Status.OK, State.HOLD, 0, (Command(0, Intent.HOLD),))
        self.assertEqual(bridge.actions(snapshot, hold), [])

    def test_reject_duplicate_and_new_friendly_tags(self):
        friend, enemy = self.units()
        bridge = RoundBridge([friend], (0,0), (0,0))
        with self.assertRaises(ProtocolError): bridge.snapshot([friend, friend], [])
        with self.assertRaises(ProtocolError): bridge.snapshot([enemy], [])

    def test_single_step_failure_never_applies_or_advances(self):
        friend, enemy = self.units()
        class Backend:
            def observe(self): return [friend], [enemy]
            def apply(self, _): raise AssertionError("must not apply")
            def step(self, _): raise AssertionError("must not advance")
        class BrokenTransport:
            def decide(self, *args): raise DecisionTimeout("test failure")
        with self.assertRaises(DecisionTimeout):
            single_step(Backend(), BrokenTransport(), RoundBridge([friend], (0,0), (0,0)), 1, 8)

    def test_single_step_validated_native_tags_then_step(self):
        friend, enemy = self.units()
        events = []
        class Backend:
            def observe(self): return [friend], [enemy]
            def current_orders(self): return {}
            def apply(self, actions): events.append(("apply", actions))
            def step(self, loops): events.append(("step", loops))
        def response(f, _):
            if f.kind == Kind.START: return ack(f)
            payload = bytes([0,2,1,0,1,0,0,0,0,1,0,0,0,0,0,0])
            return Frame(Kind.RESULT, f.round_id, f.snapshot_id, payload).encode()
        clock = Clock()
        transport = Transport(Serial(clock, response), clock=clock, sleep=clock.sleep)
        transport.start(1)
        single_step(Backend(), transport, RoundBridge([friend], (0,0), (0,0)), 1, 8)
        self.assertEqual(events, [("apply", [(100, ("attack",999))]), ("step",8)])


if __name__ == "__main__":
    unittest.main()
