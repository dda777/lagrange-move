#[test_only]
module academy_core::lifecycle_tests;

use academy_core::{
    core::{Self, Academy, AcademyAdminCap, Quest},
    test_check_a,
    test_check_b,
    test_identity,
    test_reward
};
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

fun new_quest_with(
    s: &mut Scenario,
    author: address,
    academy_id: ID,
    checks: vector<core::Requirement>,
    rewards: vector<core::Requirement>,
): ID {
    s.next_tx(author);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let quest_id = core::create_quest(
        &mut academy,
        &cap,
        test_identity::requirement(),
        checks,
        rewards,
        utf8(b"ipfs://quest"),
        x"02",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    quest_id
}

fun new_simple_quest(s: &mut Scenario, author: address, academy_id: ID): ID {
    new_quest_with(s, author, academy_id, vector[], vector[])
}

fun add_prereq(s: &mut Scenario, author: address, quest_id: ID, prereq_id: ID) {
    s.next_tx(author);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let prereq = s.take_shared_by_id<Quest>(prereq_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.add_prerequisite(&cap, &prereq);
    s.return_to_sender(cap);
    ts::return_shared(quest);
    ts::return_shared(prereq);
}

fun claim_simple(s: &mut Scenario, quest_id: ID, sender: address, game_id: u64, prereqs: vector<ID>) {
    s.next_tx(sender);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), game_id, sender);
    prereqs.do!(|prereq_id| {
        let prereq = s.take_shared_by_id<Quest>(prereq_id);
        t.prove_prereq(&prereq);
        ts::return_shared(prereq);
    });
    let rt = core::complete(t, &mut quest);
    core::finish(rt);
    ts::return_shared(quest);
}

fun evidence(n: u8): ID { object::id_from_address(sui::address::from_u256(n as u256)) }

#[test]
fun quest_with_only_identity_can_be_claimed() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    claim_simple(&mut s, quest_id, PLAYER, 101, vector[]);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.has_player_claimed(tenant(), 101));
    assert!(quest.claims() == 1);
    ts::return_shared(quest);
    s.end();
}

#[test]
fun add_and_remove_prerequisites() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    let c = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, c, a);
    let effects = s.next_tx(AUTHOR);
    assert!(effects.num_user_events() == 1);
    add_prereq(&mut s, AUTHOR, c, b);

    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(c);
    assert!(quest.prerequisites() == vector[a, b]);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.remove_prerequisite(&cap, a);
    assert!(quest.prerequisites() == vector[b]);
    s.return_to_sender(cap);
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = core::EWrongAcademy)]
fun add_prerequisite_from_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let other_academy = new_academy(&mut s, OTHER_AUTHOR);
    let quest = new_simple_quest(&mut s, AUTHOR, academy_id);
    let foreign = new_simple_quest(&mut s, OTHER_AUTHOR, other_academy);
    add_prereq(&mut s, AUTHOR, quest, foreign);
    s.end();
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun add_prerequisite_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let _other = new_academy(&mut s, OTHER_AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, OTHER_AUTHOR, b, a);
    s.end();
}

#[test, expected_failure(abort_code = core::EPrerequisiteDuplicate)]
fun add_same_prerequisite_twice_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    add_prereq(&mut s, AUTHOR, b, a);
    s.end();
}

#[test, expected_failure(abort_code = core::EPrerequisiteCycle)]
fun direct_prerequisite_cycle_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    add_prereq(&mut s, AUTHOR, a, b);
    s.end();
}

#[test, expected_failure(abort_code = core::ENotPrerequisite)]
fun remove_missing_prerequisite_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(b);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.remove_prerequisite(&cap, a);
    abort
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun add_prerequisite_of_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut prereq = s.take_shared_by_id<Quest>(a);
    prereq.set_quest_version_for_testing(2);
    ts::return_shared(prereq);
    add_prereq(&mut s, AUTHOR, b, a);
    s.end();
}

#[test]
fun prerequisite_proven_after_completion() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 101, vector[a]);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(b);
    assert!(quest.has_player_claimed(tenant(), 101));
    ts::return_shared(quest);
    s.end();
}

#[test]
fun several_prerequisites_can_be_proven_in_any_order() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    let final_quest = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, final_quest, a);
    add_prereq(&mut s, AUTHOR, final_quest, b);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 101, vector[]);
    claim_simple(&mut s, final_quest, PLAYER, 101, vector[b, a]);
    s.end();
}

#[test, expected_failure(abort_code = core::EPrerequisitesPending)]
fun claim_without_proving_prerequisite_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 101, vector[]);
    s.end();
}

#[test, expected_failure(abort_code = core::EPrerequisitesPending)]
fun claim_with_only_some_prerequisites_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    let final_quest = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, final_quest, a);
    add_prereq(&mut s, AUTHOR, final_quest, b);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    claim_simple(&mut s, final_quest, PLAYER, 101, vector[a]);
    s.end();
}

#[test, expected_failure(abort_code = core::EPrerequisiteNotCompleted)]
fun prerequisite_not_completed_by_player_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, b, PLAYER, 101, vector[a]);
    s.end();
}

#[test, expected_failure(abort_code = core::EPrerequisiteNotCompleted)]
fun prerequisite_completed_by_other_character_does_not_count() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER_2, 202, vector[]);
    claim_simple(&mut s, b, PLAYER, 101, vector[a]);
    s.end();
}

#[test]
fun prerequisite_claimed_by_wallet_counts_for_its_other_character() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 102, vector[a]);
    s.next_tx(PLAYER);
    let quest_a = s.take_shared_by_id<Quest>(a);
    let quest_b = s.take_shared_by_id<Quest>(b);
    assert!(!quest_a.has_player_claimed(tenant(), 102));
    assert!(quest_b.has_player_claimed(tenant(), 102));
    assert!(quest_b.has_wallet_claimed(PLAYER));
    ts::return_shared(quest_a);
    ts::return_shared(quest_b);
    s.end();
}

#[test, expected_failure(abort_code = core::EPrerequisiteNotCompleted)]
fun prerequisite_claimed_by_other_wallet_does_not_count() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER_2, 202, vector[]);
    claim_simple(&mut s, b, PLAYER, 102, vector[a]);
    s.end();
}

#[test, expected_failure(abort_code = core::EAlreadyClaimedByWallet)]
fun second_character_of_wallet_still_cannot_reclaim_prerequisite() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 102, vector[a]);
    claim_simple(&mut s, a, PLAYER, 102, vector[]);
    s.end();
}

#[test, expected_failure(abort_code = core::EWrongAcademy)]
fun prerequisite_from_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let other_academy = new_academy(&mut s, OTHER_AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    let foreign = new_simple_quest(&mut s, OTHER_AUTHOR, other_academy);
    claim_simple(&mut s, foreign, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 101, vector[foreign]);
    s.end();
}

#[test, expected_failure(abort_code = core::ENotPrerequisite)]
fun quest_of_same_academy_that_is_not_prerequisite_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    let unrelated = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, unrelated, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 101, vector[unrelated]);
    s.end();
}

#[test, expected_failure(abort_code = core::ENotPrerequisite)]
fun proving_same_prerequisite_twice_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(b);
    let prereq = s.take_shared_by_id<Quest>(a);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    t.prove_prereq(&prereq);
    assert!(t.pending_prerequisites().is_empty());
    t.prove_prereq(&prereq);
    abort
}

#[test, expected_failure(abort_code = core::ENoIdentity)]
fun prove_prereq_before_bind_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(b);
    let prereq = s.take_shared_by_id<Quest>(a);
    let mut t = core::begin_claim(&quest);
    t.prove_prereq(&prereq);
    abort
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun prove_prereq_of_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    s.next_tx(AUTHOR);
    let mut prereq = s.take_shared_by_id<Quest>(a);
    prereq.set_quest_version_for_testing(2);
    ts::return_shared(prereq);
    claim_simple(&mut s, b, PLAYER, 101, vector[a]);
    s.end();
}

fun claimed_quest(s: &mut Scenario): (ID, ID) {
    let academy_id = new_academy(s, AUTHOR);
    let quest_id = new_quest_with(
        s,
        AUTHOR,
        academy_id,
        vector[test_check_a::requirement(7)],
        vector[test_reward::requirement(1, false)],
    );
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_check_a::check_with_evidence(&mut t, evidence(1));
    let mut rt = core::complete(t, &mut quest);
    test_reward::pay(&mut rt);
    core::finish(rt);
    ts::return_shared(quest);
    (academy_id, quest_id)
}

#[test]
fun rules_can_change_before_first_claim() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_checks(&cap, vector[test_check_b::requirement()]);
    quest.set_rewards(&cap, vector[test_reward::requirement(3, true)]);
    quest.set_identity(&cap, test_check_a::requirement(0));
    assert!(quest.checks() == vector[test_check_b::requirement()]);
    assert!(quest.rewards() == vector[test_reward::requirement(3, true)]);
    assert!(quest.identity() == test_check_a::requirement(0));
    s.return_to_sender(cap);
    ts::return_shared(quest);
    let effects = s.next_tx(AUTHOR);
    assert!(effects.num_user_events() == 3);
    s.end();
}

#[test, expected_failure(abort_code = core::ERulesFrozen)]
fun set_checks_after_claim_fails() {
    let mut s = ts::begin(AUTHOR);
    let (_, quest_id) = claimed_quest(&mut s);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_checks(&cap, vector[]);
    abort
}

#[test, expected_failure(abort_code = core::ERulesFrozen)]
fun set_rewards_after_claim_fails() {
    let mut s = ts::begin(AUTHOR);
    let (_, quest_id) = claimed_quest(&mut s);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_rewards(&cap, vector[]);
    abort
}

#[test, expected_failure(abort_code = core::ERulesFrozen)]
fun set_identity_after_claim_fails() {
    let mut s = ts::begin(AUTHOR);
    let (_, quest_id) = claimed_quest(&mut s);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_identity(&cap, test_check_b::requirement());
    abort
}

#[test, expected_failure(abort_code = core::ERulesFrozen)]
fun add_prerequisite_after_claim_fails() {
    let mut s = ts::begin(AUTHOR);
    let (academy_id, quest_id) = claimed_quest(&mut s);
    let other = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, quest_id, other);
    s.end();
}

#[test, expected_failure(abort_code = core::ERulesFrozen)]
fun remove_prerequisite_after_claim_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let a = new_simple_quest(&mut s, AUTHOR, academy_id);
    let b = new_simple_quest(&mut s, AUTHOR, academy_id);
    add_prereq(&mut s, AUTHOR, b, a);
    claim_simple(&mut s, a, PLAYER, 101, vector[]);
    claim_simple(&mut s, b, PLAYER, 101, vector[a]);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(b);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.remove_prerequisite(&cap, a);
    abort
}

#[test]
fun content_and_active_change_after_claim() {
    let mut s = ts::begin(AUTHOR);
    let (_, quest_id) = claimed_quest(&mut s);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_content(&cap, utf8(b"ipfs://quest-v2"), x"03");
    quest.set_active(&cap, false);
    assert!(quest.quest_content_uri() == utf8(b"ipfs://quest-v2"));
    assert!(quest.quest_content_hash() == x"03");
    assert!(!quest.is_active());
    quest.set_active(&cap, true);
    assert!(quest.is_active());
    s.return_to_sender(cap);
    ts::return_shared(quest);
    let effects = s.next_tx(AUTHOR);
    assert!(effects.num_user_events() == 3);
    s.end();
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun set_active_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let _other = new_academy(&mut s, OTHER_AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(OTHER_AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_active(&cap, false);
    abort
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun set_content_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let _other = new_academy(&mut s, OTHER_AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(OTHER_AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_content(&cap, utf8(b"evil"), x"");
    abort
}

#[test]
fun academy_content_can_be_updated() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    s.next_tx(AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    academy.set_academy_content(&cap, utf8(b"https://example.org/academy-v2.json"), x"04");
    assert!(academy.academy_content_uri() == utf8(b"https://example.org/academy-v2.json"));
    assert!(academy.academy_content_hash() == x"04");
    s.return_to_sender(cap);
    ts::return_shared(academy);
    let effects = s.next_tx(AUTHOR);
    assert!(effects.num_user_events() == 1);
    s.end();
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun set_academy_content_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let _other = new_academy(&mut s, OTHER_AUTHOR);
    s.next_tx(OTHER_AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    academy.set_academy_content(&cap, utf8(b"evil"), x"");
    abort
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun set_academy_content_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    s.next_tx(AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    core::set_academy_version_for_testing(&mut academy, 2);
    academy.set_academy_content(&cap, utf8(b"v"), x"");
    abort
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun set_checks_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let _other = new_academy(&mut s, OTHER_AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(OTHER_AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_checks(&cap, vector[]);
    abort
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun set_active_on_quest_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    quest.set_quest_version_for_testing(2);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_active(&cap, false);
    abort
}

#[test, expected_failure(abort_code = core::EQuestInactive)]
fun deactivated_quest_rejects_claim() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_active(&cap, false);
    s.return_to_sender(cap);
    ts::return_shared(quest);
    claim_simple(&mut s, quest_id, PLAYER, 101, vector[]);
    s.end();
}

#[test]
fun reactivated_quest_accepts_claim() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    quest.set_active(&cap, false);
    quest.set_active(&cap, true);
    s.return_to_sender(cap);
    ts::return_shared(quest);
    claim_simple(&mut s, quest_id, PLAYER, 101, vector[]);
    s.end();
}

#[test, expected_failure(abort_code = core::ERulesChanged)]
fun rules_changed_between_begin_claim_and_complete_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(
        &mut s,
        AUTHOR,
        academy_id,
        vector[],
        vector[test_reward::requirement(1, false)],
    );
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, AUTHOR);
    quest.set_rewards(&cap, vector[]);
    let _rt = core::complete(t, &mut quest);
    abort
}

#[test, expected_failure(abort_code = core::EQuestInactive)]
fun deactivated_between_begin_claim_and_complete_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, AUTHOR);
    quest.set_active(&cap, false);
    let _rt = core::complete(t, &mut quest);
    abort
}

#[test]
fun content_change_between_begin_claim_and_complete_is_fine() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_simple_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(AUTHOR);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, AUTHOR);
    quest.set_content(&cap, utf8(b"ipfs://typo-fixed"), x"");
    let rt = core::complete(t, &mut quest);
    core::finish(rt);
    s.return_to_sender(cap);
    ts::return_shared(quest);
    s.end();
}
