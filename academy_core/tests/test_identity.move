#[test_only]
module academy_core::test_identity;

use academy_core::core::{Self, ClaimTicket, Requirement};
use std::{internal, string::String};

public struct TestIdentity() has drop;

public fun requirement(): Requirement { core::requirement(TestIdentity()) }

public fun bind(t: &mut ClaimTicket, tenant: String, game_id: u64, recipient: address) {
    t.bind_player(internal::permit<TestIdentity>(), tenant, game_id, recipient);
}
