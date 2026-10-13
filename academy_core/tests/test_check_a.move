#[test_only]
module academy_core::test_check_a;

use academy_core::core::{Self, ClaimTicket, Requirement};
use std::internal;

public struct CheckA has drop { value: u64 }

public fun requirement(value: u64): Requirement { core::requirement(CheckA { value }) }

public fun check(t: &mut ClaimTicket): u64 {
    let data = t.take_check(internal::permit<CheckA>());
    sui::bcs::new(data).peel_u64()
}

public fun check_with_evidence(t: &mut ClaimTicket, evidence: ID) {
    let _ = check(t);
    t.add_evidence(internal::permit<CheckA>(), evidence);
}

public fun evidence_only(t: &mut ClaimTicket, evidence: ID) {
    t.add_evidence(internal::permit<CheckA>(), evidence);
}
