#[test_only]
module academy_core::test_reward;

use academy_core::core::{Self, RewardTicket, Requirement};
use std::internal;

public struct TestReward has drop { amount: u64, optional: bool }

public fun requirement(amount: u64, optional: bool): Requirement {
    core::requirement(TestReward { amount, optional })
}

public fun pay(rt: &mut RewardTicket): (ID, address, u64) {
    let (quest_id, recipient, data) = rt.take_reward(internal::permit<TestReward>());
    let amount = sui::bcs::new(data).peel_u64();
    rt.record_payment(internal::permit<TestReward>(), amount);
    (quest_id, recipient, amount)
}

public fun skip(rt: &mut RewardTicket) {
    let data = rt.skip_optional_reward(internal::permit<TestReward>());
    let mut r = sui::bcs::new(data);
    let _amount = r.peel_u64();
    assert!(r.peel_bool(), 0);
}

public fun skip_then_record(rt: &mut RewardTicket) {
    let _ = rt.skip_optional_reward(internal::permit<TestReward>());
    rt.record_payment(internal::permit<TestReward>(), 1);
}

public fun peek_amount(rt: &academy_core::core::RewardTicket): u64 {
    let data = rt.peek_reward<TestReward>();
    sui::bcs::new(data).peel_u64()
}
