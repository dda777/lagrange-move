#[test_only]
module academy_core::migrate_tests;

use academy_core::{core::{Self, Academy, AcademyAdminCap, Quest}, test_identity};
use std::string::{String, utf8};
use sui::test_scenario::{Self as ts, Scenario};

const AUTHOR: address = @0xA1;
const OTHER_AUTHOR: address = @0xA2;
const PLAYER: address = @0xB1;
const PLAYER_2: address = @0xB2;

fun tenant(): String { utf8(b"TEST") }

fun new_academy(s: &mut Scenario, author: address): ID {
    s.next_tx(author);
    let cap = core::create_academy(utf8(b"Academy"), utf8(b""), x"", s.ctx());
    let academy_id = cap.admin_academy_id();
    transfer::public_transfer(cap, author);
    academy_id
}

fun new_quest(s: &mut Scenario, author: address, academy_id: ID): ID {
    s.next_tx(author);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let quest_id = core::create_quest(
        &mut academy,
        &cap,
        test_identity::requirement(),
        vector[],
        vector[],
        utf8(b"walrus://q"),
        x"01",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    quest_id
}

fun claim(s: &mut Scenario, quest_id: ID, sender: address, game_id: u64) {
    s.next_tx(sender);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), game_id, sender);
    let rt = core::complete(t, &mut quest);
    core::finish(rt);
    ts::return_shared(quest);
}

fun old_version(): u64 { core::package_version() - 1 }

fun make_quest_old(s: &mut Scenario, quest_id: ID) {
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    quest.set_quest_version_for_testing(old_version());
    ts::return_shared(quest);
}

fun make_academy_old(s: &mut Scenario, academy_id: ID) {
    s.next_tx(AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    academy.set_academy_version_for_testing(old_version());
    ts::return_shared(academy);
}

fun migrate_quest(s: &mut Scenario, author: address, quest_id: ID) {
    s.next_tx(author);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.migrate_quest(&cap);
    s.return_to_sender(cap);
    ts::return_shared(quest);
}

fun migrate_academy(s: &mut Scenario, author: address, academy_id: ID) {
    s.next_tx(author);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    academy.migrate_academy(&cap);
    s.return_to_sender(cap);
    ts::return_shared(academy);
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun old_quest_is_blocked_before_migrate() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest(&mut s, AUTHOR, academy_id);
    make_quest_old(&mut s, quest_id);
    claim(&mut s, quest_id, PLAYER, 101);
    abort
}

#[test]
fun old_quest_works_after_migrate_and_keeps_markers() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest(&mut s, AUTHOR, academy_id);
    claim(&mut s, quest_id, PLAYER, 101);
    make_quest_old(&mut s, quest_id);
    migrate_quest(&mut s, AUTHOR, quest_id);

    s.next_tx(AUTHOR);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.quest_version() == core::package_version());
    assert!(quest.has_player_claimed(tenant(), 101));
    assert!(quest.claims() == 1);
    ts::return_shared(quest);

    claim(&mut s, quest_id, PLAYER_2, 202);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_content(&cap, utf8(b"walrus://q2"), x"02");
    assert!(quest.claims() == 2);
    s.return_to_sender(cap);
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = core::EAlreadyMigrated)]
fun migrate_current_quest_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest(&mut s, AUTHOR, academy_id);
    migrate_quest(&mut s, AUTHOR, quest_id);
    abort
}

#[test, expected_failure(abort_code = core::EAlreadyMigrated)]
fun migrate_newer_quest_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    quest.set_quest_version_for_testing(core::package_version() + 1);
    ts::return_shared(quest);
    migrate_quest(&mut s, AUTHOR, quest_id);
    abort
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun migrate_quest_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest(&mut s, AUTHOR, academy_id);
    make_quest_old(&mut s, quest_id);
    new_academy(&mut s, OTHER_AUTHOR);
    migrate_quest(&mut s, OTHER_AUTHOR, quest_id);
    abort
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun old_academy_is_blocked_before_migrate() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    make_academy_old(&mut s, academy_id);
    new_quest(&mut s, AUTHOR, academy_id);
    abort
}

#[test]
fun old_academy_works_after_migrate() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let first = new_quest(&mut s, AUTHOR, academy_id);
    make_academy_old(&mut s, academy_id);
    migrate_academy(&mut s, AUTHOR, academy_id);
    let second = new_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let academy = s.take_shared_by_id<Academy>(academy_id);
    assert!(academy.academy_version() == core::package_version());
    assert!(academy.quests() == vector[first, second]);
    ts::return_shared(academy);
    s.end();
}

#[test, expected_failure(abort_code = core::EAlreadyMigrated)]
fun migrate_current_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    migrate_academy(&mut s, AUTHOR, academy_id);
    abort
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun migrate_academy_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    make_academy_old(&mut s, academy_id);
    new_academy(&mut s, OTHER_AUTHOR);
    migrate_academy(&mut s, OTHER_AUTHOR, academy_id);
    abort
}
