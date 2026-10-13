#[test_only]
module academy_core::verified_checks_tests;

use academy_core::{
    test_check_a::{Self, CheckA},
    test_check_b::CheckB,
    test_identity,
    verified_checks::{Self, VerifiedChecks, PlatformAdminCap}
};
use std::type_name;
use sui::{event, test_scenario::{Self as ts, Scenario}};

const PUBLISHER: address = @0xC0;
const STRANGER: address = @0xC1;

fun setup(): Scenario {
    let mut s = ts::begin(PUBLISHER);
    verified_checks::init_for_testing(s.ctx());
    s
}

#[test]
fun init_shares_registry_and_sends_cap_to_publisher() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    assert!(s.has_most_recent_for_sender<PlatformAdminCap>());
    let vc = s.take_shared<VerifiedChecks>();
    assert!(vc.verified_types().is_empty());
    assert!(!vc.is_verified<CheckA>());
    ts::return_shared(vc);
    s.next_tx(STRANGER);
    assert!(!s.has_most_recent_for_sender<PlatformAdminCap>());
    s.end();
}

#[test]
fun add_and_remove_with_events() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();

    vc.add<CheckA>(&cap);
    assert!(vc.is_verified<CheckA>());
    assert!(!vc.is_verified<CheckB>());
    assert!(vc.verified_types() == vector[type_name::with_original_ids<CheckA>()]);
    let added = event::events_by_type<verified_checks::VerifiedCheckAdded>();
    assert!(added.length() == 1);

    vc.add<CheckB>(&cap);
    vc.remove<CheckA>(&cap);
    assert!(!vc.is_verified<CheckA>());
    assert!(vc.is_verified<CheckB>());
    let removed = event::events_by_type<verified_checks::VerifiedCheckRemoved>();
    assert!(removed.length() == 1);

    s.return_to_sender(cap);
    ts::return_shared(vc);
    s.end();
}

#[test]
fun requirement_identity_matches_verified_type() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    let req = test_check_a::requirement(7);
    assert!(!vc.is_requirement_verified(&req));
    vc.add<CheckA>(&cap);
    assert!(vc.is_requirement_verified(&req));
    assert!(vc.is_type_verified(&req.requirement_type()));
    assert!(!vc.is_requirement_verified(&test_identity::requirement()));
    s.return_to_sender(cap);
    ts::return_shared(vc);
    s.end();
}

#[test, expected_failure(abort_code = verified_checks::EAlreadyVerified)]
fun add_twice_aborts() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    vc.add<CheckA>(&cap);
    vc.add<CheckA>(&cap);
    abort
}

#[test, expected_failure(abort_code = verified_checks::ENotVerified)]
fun remove_missing_aborts() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    vc.remove<CheckA>(&cap);
    abort
}

#[test, expected_failure(abort_code = verified_checks::EWrongVersion)]
fun add_on_old_version_aborts() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    vc.set_version_for_testing(0);
    vc.add<CheckA>(&cap);
    abort
}

#[test, expected_failure(abort_code = verified_checks::EWrongVersion)]
fun remove_on_old_version_aborts() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    vc.add<CheckA>(&cap);
    vc.set_version_for_testing(0);
    vc.remove<CheckA>(&cap);
    abort
}

#[test, expected_failure(abort_code = verified_checks::EWrongVersion)]
fun is_verified_on_old_version_aborts() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    vc.set_version_for_testing(0);
    let _ = vc.is_verified<CheckA>();
    abort
}

#[test]
fun old_registry_works_after_migrate() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    vc.add<CheckA>(&cap);
    vc.set_version_for_testing(0);
    vc.migrate(&cap);
    assert!(vc.version() == 1);
    assert!(vc.is_verified<CheckA>());
    vc.add<CheckB>(&cap);
    assert!(vc.is_verified<CheckB>());
    ts::return_shared(vc);
    s.return_to_sender(cap);
    s.end();
}

#[test, expected_failure(abort_code = verified_checks::EAlreadyMigrated)]
fun migrate_current_registry_aborts() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    vc.migrate(&cap);
    abort
}

#[test, expected_failure(abort_code = verified_checks::EAlreadyMigrated)]
fun migrate_newer_registry_aborts() {
    let mut s = setup();
    s.next_tx(PUBLISHER);
    let mut vc = s.take_shared<VerifiedChecks>();
    let cap = s.take_from_sender<PlatformAdminCap>();
    vc.set_version_for_testing(2);
    vc.migrate(&cap);
    abort
}
