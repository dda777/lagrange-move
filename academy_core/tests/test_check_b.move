#[test_only]
module academy_core::test_check_b;

use academy_core::core::{Self, ClaimTicket, Requirement};
use std::internal;

public struct CheckB has drop {}

public fun requirement(): Requirement { core::requirement(CheckB {}) }

public fun check(t: &mut ClaimTicket) {
    let _ = t.take_check(internal::permit<CheckB>());
}
