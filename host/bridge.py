"""SC2 integration boundary. Backend launch/API binding must be qualified separately."""
from dataclasses import dataclass
from .protocol import Intent, ProtocolError, Snapshot, Unit, fixed


@dataclass(frozen=True)
class ObservedUnit:
    tag: int
    x: float
    y: float
    health: float
    max_health: float
    damage: float
    effective_reach: float
    ready: bool = False


class RoundBridge:
    """One observed round, no tag reuse, no hidden friendly tactical policy.

    Call begin with the complete, qualified initial squad. Convert only current
    visible eligible enemies. A backend must revalidate tags against its current
    observation immediately before applying the returned actions.
    """
    def __init__(self, initial_friends, objective, safety):
        initial_friends = tuple(initial_friends)
        self.tags = ({}, {})
        self.previous_orders = {}
        self.objective = tuple(fixed(v, 6) for v in objective)
        self.safety = tuple(fixed(v, 6) for v in safety)
        self.initial_health = sum(fixed(u.max_health, 4) for u in initial_friends)
        self.initial_tags = {u.tag for u in initial_friends}
        self.initial_maxima = {u.tag: fixed(u.max_health, 4) for u in initial_friends}
        self.snapshot(initial_friends, ())  # validate initial squad, seed stable indices

    def records(self, units, side):
        records = []
        tags = set()
        for u in units:
            if type(u.tag) is not int or not 0 < u.tag < 1 << 64 or u.tag in tags:
                raise ProtocolError("invalid/duplicate native tag")
            tags.add(u.tag)
            if side == 0 and u.tag not in self.initial_tags:
                raise ProtocolError("new friendly unit within round")
            if side == 0 and fixed(u.max_health, 4) != self.initial_maxima[u.tag]:
                raise ProtocolError("friendly maximum health changed within round")
            mapping = self.tags[side]
            if u.tag not in mapping:
                if len(mapping) == 16:
                    raise ProtocolError("more than 16 distinct tags in round")
                mapping[u.tag] = len(mapping)
            records.append(Unit(mapping[u.tag], int(u.ready) if side == 0 else 0,
                                fixed(u.x, 6), fixed(u.y, 6), fixed(u.health, 4),
                                fixed(u.max_health, 4), fixed(u.damage, 4),
                                fixed(u.effective_reach, 6)))
        return tuple(sorted(records, key=lambda u: u.index))

    def snapshot(self, friends, enemies):
        # Stable assignment for initial/new enemy tags independent of observation ordering.
        friends, enemies = sorted(friends, key=lambda u: u.tag), sorted(enemies, key=lambda u: u.tag)
        result = Snapshot(self.records(friends, 0), self.records(enemies, 1),
                          self.initial_health, self.objective, self.safety)
        result.encode()
        return result

    def actions(self, snapshot, reply, current_orders=None):
        """Return native-tag intents. HOLD submits nothing; validate entire reply first."""
        reply.validate(snapshot)
        if current_orders is not None:
            # Observed orders are authoritative; an old confirmed order may have ended.
            self.previous_orders = dict(current_orders)
        friend_tags = {index: tag for tag, index in self.tags[0].items()}
        enemy_tags = {index: tag for tag, index in self.tags[1].items()}
        actions = []
        for c in reply.commands:
            if c.intent == Intent.HOLD:
                continue
            tag = friend_tags[c.actor]
            order = ("attack", enemy_tags[c.target]) if c.intent == Intent.ATTACK else (
                "move", c.x / 64, c.y / 64)
            if self.previous_orders.get(tag) != order:
                actions.append((tag, order))
        return actions

    def confirm_actions(self, actions):
        """Only after the API confirms success; failed orders must not be deduplicated."""
        for tag, order in actions:
            self.previous_orders[tag] = order


def single_step(backend, transport, bridge, snapshot_id, game_loops):
    """Backend: observe()->(friends,enemies), apply(actions), step(game_loops).

    current_orders() returns native tag -> normalized (attack/move) order from
    the current observation. apply must validate current tags and raise on any SC2 action failure. The
    actual map/client/API binding is intentionally a required caller dependency.
    """
    if type(game_loops) is not int or game_loops <= 0:
        raise ValueError("positive game step required")
    friends, enemies = backend.observe()
    snapshot = bridge.snapshot(friends, enemies)
    reply = transport.decide(snapshot, snapshot_id)
    actions = bridge.actions(snapshot, reply, current_orders=backend.current_orders())
    backend.apply(actions)
    bridge.confirm_actions(actions)
    backend.step(game_loops)
    return reply
