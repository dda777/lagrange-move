#[test_only]
module academy_rewards::test_identity;

use academy_core::core::ClaimTicket;
use std::{internal, string::String};

public struct TestIdentity() has drop;

public fun requirement(): academy_core::core::Requirement {
    academy_core::core::requirement(TestIdentity())
}

public fun bind(t: &mut ClaimTicket, tenant: String, game_id: u64, recipient: address) {
    t.bind_player(internal::permit<TestIdentity>(), tenant, game_id, recipient);
}

public struct OtherReward has drop {}

public fun other_reward(): academy_core::core::Requirement {
    academy_core::core::requirement(OtherReward {})
}
