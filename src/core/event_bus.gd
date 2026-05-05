extends Node

# Decoupled in-process signal hub. Anyone can emit/subscribe. Subscribers
# never reach for `get_first_node_in_group("arena")` to talk to systems.
#
# Convention: signals are emitted only on the simulation authority (host or
# offline). Pure view systems subscribe and react locally.

# Combat / lifecycle.
signal damage_dealt(target: Node, amount: float, src_team: String)
signal enemy_killed(enemy: Node, killer_peer: int)
signal player_downed(peer_id: int)
signal player_revived(peer_id: int)
signal player_healed(peer_id: int, amount: float)

# Progression.
signal xp_gained(amount: int, total: int)
signal level_up(new_level: int)
signal upgrade_picked(peer_id: int, upgrade_id: StringName)

# Run lifecycle.
signal run_started
signal run_ended(won: bool)
signal time_synced(t: float)
