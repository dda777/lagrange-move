#[test_only]
module academy_core::test_attacker;

use academy_core::core::{ClaimTicket, RewardTicket};
use std::{internal, string::String};

public struct Attacker() has drop;

public fun bind(t: &mut ClaimTicket, tenant: String, game_id: u64, recipient: address) {
    t.bind_player(internal::permit<Attacker>(), tenant, game_id, recipient);
}

public fun burn_evidence(t: &mut ClaimTicket, object_id: ID) {
    t.add_evidence(internal::permit<Attacker>(), object_id);
}

public fun fake_payment(rt: &RewardTicket) {
    rt.record_payment(internal::permit<Attacker>(), 1_000_000);
}
