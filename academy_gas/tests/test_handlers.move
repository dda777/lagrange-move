#[test_only]
module academy_gas::test_handlers;

use academy_core::core::{Self, ClaimTicket, Requirement, RewardTicket};
use std::{internal, string::String};

public struct TestIdentity() has drop;

public struct TestReward() has drop;

public fun identity(): Requirement { core::requirement(TestIdentity()) }

public fun bind(t: &mut ClaimTicket, tenant: String, game_id: u64, recipient: address) {
    t.bind_player(internal::permit<TestIdentity>(), tenant, game_id, recipient);
}

public fun reward(): Requirement { core::requirement(TestReward()) }

public fun pay(rt: &mut RewardTicket) {
    rt.take_reward(internal::permit<TestReward>());
    rt.record_payment(internal::permit<TestReward>(), 1);
}
