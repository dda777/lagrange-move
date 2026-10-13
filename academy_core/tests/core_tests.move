#[test_only]
module academy_core::core_tests;

use academy_core::{
    core::{Self, Academy, AcademyAdminCap, Quest},
    test_attacker,
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
    let cap = core::create_academy(utf8(b"Academy"), utf8(b"ipfs://academy"), x"01", s.ctx());
    let academy_id = cap.admin_academy_id();
    transfer::public_transfer(cap, author);
    academy_id
}

fun new_quest(s: &mut Scenario, author: address, academy_id: ID): ID {
    new_quest_with(
        s,
        author,
        academy_id,
        vector[test_check_a::requirement(7), test_check_b::requirement()],
        vector[test_reward::requirement(100, false)],
    )
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

fun setup(s: &mut Scenario): ID {
    let academy_id = new_academy(s, AUTHOR);
    new_quest(s, AUTHOR, academy_id)
}

fun claim(s: &mut Scenario, quest_id: ID, sender: address, game_id: u64, evidence: ID) {
    s.next_tx(sender);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), game_id, sender);
    test_check_a::check_with_evidence(&mut t, evidence);
    test_check_b::check(&mut t);
    let mut rt = core::complete(t, &mut quest);
    let (paid_quest, recipient, amount) = test_reward::pay(&mut rt);
    assert!(paid_quest == quest_id);
    assert!(recipient == sender);
    assert!(amount == 100);
    core::finish(rt);
    ts::return_shared(quest);
}

fun evidence(n: u8): ID { object::id_from_address(sui::address::from_u256(n as u256)) }

#[test]
fun create_academy_and_quest() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest(&mut s, AUTHOR, academy_id);

    s.next_tx(AUTHOR);
    let academy = s.take_shared_by_id<Academy>(academy_id);
    assert!(academy.name() == utf8(b"Academy"));
    assert!(academy.academy_content_uri() == utf8(b"ipfs://academy"));
    assert!(academy.academy_content_hash() == x"01");
    assert!(academy.quests() == vector[quest_id]);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.academy_id() == academy_id);
    assert!(quest.identity() == test_identity::requirement());
    assert!(quest.checks().length() == 2);
    assert!(quest.checks()[0] == test_check_a::requirement(7));
    assert!(quest.checks()[1] == test_check_b::requirement());
    assert!(quest.rewards() == vector[test_reward::requirement(100, false)]);
    assert!(quest.prerequisites().is_empty());
    assert!(quest.is_active());
    assert!(quest.claims() == 0);
    assert!(quest.quest_content_uri() == utf8(b"ipfs://quest"));
    assert!(quest.quest_content_hash() == x"02");
    ts::return_shared(academy);
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = core::ENotAcademyAdmin)]
fun create_quest_with_cap_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let _other = new_academy(&mut s, OTHER_AUTHOR);
    new_quest(&mut s, OTHER_AUTHOR, academy_id);
    s.end();
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun create_quest_in_academy_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    s.next_tx(AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    academy.set_academy_version_for_testing(0);
    ts::return_shared(academy);
    new_quest(&mut s, AUTHOR, academy_id);
    s.end();
}

#[test]
fun claim_creates_markers_and_counts() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    claim(&mut s, quest_id, PLAYER, 101, evidence(1));

    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.has_player_claimed(tenant(), 101));
    assert!(!quest.has_player_claimed(tenant(), 102));
    assert!(!quest.has_player_claimed(utf8(b"OTHER"), 101));
    assert!(quest.has_wallet_claimed(PLAYER));
    assert!(!quest.has_wallet_claimed(PLAYER_2));
    assert!(quest.is_evidence_used(evidence(1)));
    assert!(!quest.is_evidence_used(evidence(2)));
    assert!(quest.claims() == 1);
    ts::return_shared(quest);
    s.end();
}

#[test]
fun different_players_wallets_and_evidence_can_each_claim() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    claim(&mut s, quest_id, PLAYER, 101, evidence(1));
    claim(&mut s, quest_id, PLAYER_2, 102, evidence(2));
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.claims() == 2);
    ts::return_shared(quest);
    s.end();
}

#[test]
fun optional_reward_can_be_skipped() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(
        &mut s,
        AUTHOR,
        academy_id,
        vector[],
        vector[test_reward::requirement(5, true), test_reward::requirement(100, false)],
    );
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    test_reward::skip(&mut rt);
    let (_, _, amount) = test_reward::pay(&mut rt);
    assert!(amount == 100);
    core::finish(rt);
    ts::return_shared(quest);
    s.end();
}

#[test]
fun ticket_getters_expose_claim_context() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    assert!(t.claim_quest_id() == quest_id);
    assert!(t.claim_academy_id() == quest.academy_id());
    assert!(!t.is_bound());
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    assert!(t.is_bound());
    assert!(t.claim_tenant() == tenant());
    assert!(t.claim_game_id() == 101);
    assert!(t.claim_recipient() == PLAYER);
    test_check_a::check_with_evidence(&mut t, evidence(1));
    test_check_b::check(&mut t);
    let mut rt = core::complete(t, &mut quest);
    assert!(rt.reward_quest_id() == quest_id);
    assert!(rt.reward_academy_id() == quest.academy_id());
    assert!(rt.reward_tenant() == tenant());
    assert!(rt.reward_game_id() == 101);
    assert!(rt.reward_recipient() == PLAYER);
    test_reward::pay(&mut rt);
    core::finish(rt);
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = core::EChecksPending)]
fun complete_with_skipped_check_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_check_a::check(&mut t);
    let _rt = core::complete(t, &mut quest);
    abort
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun checks_in_wrong_order_fail() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_check_b::check(&mut t);
    abort
}

#[test, expected_failure(abort_code = core::ENoPendingRequirement)]
fun extra_check_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_check_a::check(&mut t);
    test_check_b::check(&mut t);
    test_check_b::check(&mut t);
    abort
}

#[test, expected_failure(abort_code = core::ERewardsPending)]
fun finish_with_unpaid_reward_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_check_a::check(&mut t);
    test_check_b::check(&mut t);
    let rt = core::complete(t, &mut quest);
    core::finish(rt);
    abort
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun reward_of_wrong_type_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(
        &mut s,
        AUTHOR,
        academy_id,
        vector[],
        vector[test_check_b::requirement()],
    );
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    test_reward::pay(&mut rt);
    abort
}

#[test, expected_failure(abort_code = core::ENoPendingRequirement)]
fun extra_reward_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(&mut s, AUTHOR, academy_id, vector[], vector[]);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    test_reward::pay(&mut rt);
    abort
}

#[test, expected_failure(abort_code = core::EWrongQuest)]
fun ticket_of_quest_a_cannot_complete_quest_b() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_a = new_quest_with(&mut s, AUTHOR, academy_id, vector[], vector[]);
    let quest_b = new_quest(&mut s, AUTHOR, academy_id);
    s.next_tx(PLAYER);
    let a = s.take_shared_by_id<Quest>(quest_a);
    let mut b = s.take_shared_by_id<Quest>(quest_b);
    let mut t = core::begin_claim(&a);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let _rt = core::complete(t, &mut b);
    abort
}

#[test, expected_failure(abort_code = core::ENoIdentity)]
fun complete_without_identity_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_check_a::check(&mut t);
    test_check_b::check(&mut t);
    let _rt = core::complete(t, &mut quest);
    abort
}

#[test, expected_failure(abort_code = core::EIdentityAlreadySet)]
fun bind_twice_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_identity::bind(&mut t, tenant(), 102, PLAYER);
    abort
}

#[test, expected_failure(abort_code = core::ENoIdentity)]
fun player_getter_before_bind_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let t = core::begin_claim(&quest);
    t.claim_game_id();
    abort
}

#[test, expected_failure(abort_code = core::EAlreadyClaimedByPlayer)]
fun second_claim_by_same_player_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    claim(&mut s, quest_id, PLAYER, 101, evidence(1));
    claim(&mut s, quest_id, PLAYER_2, 101, evidence(2));
    s.end();
}

#[test, expected_failure(abort_code = core::EAlreadyClaimedByWallet)]
fun second_claim_by_same_wallet_other_player_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    claim(&mut s, quest_id, PLAYER, 101, evidence(1));
    claim(&mut s, quest_id, PLAYER, 102, evidence(2));
    s.end();
}

#[test, expected_failure(abort_code = core::EEvidenceUsed)]
fun evidence_reused_by_other_player_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    claim(&mut s, quest_id, PLAYER, 101, evidence(1));
    claim(&mut s, quest_id, PLAYER_2, 102, evidence(1));
    s.end();
}

#[test, expected_failure(abort_code = core::EEvidenceUsed)]
fun same_evidence_twice_in_one_claim_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(
        &mut s,
        AUTHOR,
        academy_id,
        vector[test_check_a::requirement(1), test_check_a::requirement(2)],
        vector[],
    );
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_check_a::check_with_evidence(&mut t, evidence(1));
    test_check_a::check_with_evidence(&mut t, evidence(1));
    let _rt = core::complete(t, &mut quest);
    abort
}

#[test]
fun markers_are_per_quest() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_a = new_quest(&mut s, AUTHOR, academy_id);
    let quest_b = new_quest(&mut s, AUTHOR, academy_id);
    claim(&mut s, quest_a, PLAYER, 101, evidence(1));
    claim(&mut s, quest_b, PLAYER, 101, evidence(1));
    s.end();
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun begin_claim_on_quest_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    quest.set_quest_version_for_testing(2);
    let _t = core::begin_claim(&quest);
    abort
}

#[test, expected_failure(abort_code = core::EWrongVersion)]
fun complete_on_quest_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(&mut s, AUTHOR, academy_id, vector[], vector[]);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    quest.set_quest_version_for_testing(2);
    let _rt = core::complete(t, &mut quest);
    abort
}

#[test, expected_failure(abort_code = core::EQuestInactive)]
fun begin_claim_on_inactive_quest_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    quest.set_active_for_testing(false);
    let _t = core::begin_claim(&quest);
    abort
}

#[test, expected_failure(abort_code = core::EWrongIdentity)]
fun bind_by_adapter_not_trusted_by_quest_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_attacker::bind(&mut t, tenant(), 999, PLAYER);
    abort
}

#[test, expected_failure(abort_code = core::EHandlerMismatch)]
fun evidence_from_module_outside_quest_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_check_a::check_with_evidence(&mut t, evidence(1));
    test_attacker::burn_evidence(&mut t, evidence(2));
    abort
}

#[test, expected_failure(abort_code = core::EHandlerMismatch)]
fun evidence_before_any_check_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_attacker::burn_evidence(&mut t, evidence(2));
    abort
}

#[test, expected_failure(abort_code = core::EHandlerMismatch)]
fun payment_record_from_module_outside_quest_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_check_a::check(&mut t);
    test_check_b::check(&mut t);
    let mut rt = core::complete(t, &mut quest);
    test_reward::pay(&mut rt);
    test_attacker::fake_payment(&rt);
    abort
}

#[test, expected_failure(abort_code = core::EHandlerMismatch)]
fun evidence_from_earlier_check_after_next_check_taken_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = setup(&mut s);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    test_check_a::check(&mut t);
    test_check_b::check(&mut t);
    test_check_a::evidence_only(&mut t, evidence(1));
    abort
}

#[test, expected_failure(abort_code = core::EHandlerMismatch)]
fun payment_record_after_skip_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(
        &mut s,
        AUTHOR,
        academy_id,
        vector[],
        vector[test_reward::requirement(5, true)],
    );
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    test_reward::skip_then_record(&mut rt);
    abort
}

#[test]
fun peek_reward_reads_next_config_without_taking_it() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(
        &mut s,
        AUTHOR,
        academy_id,
        vector[],
        vector[test_reward::requirement(5, true), test_reward::requirement(100, false)],
    );
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    assert!(test_reward::peek_amount(&rt) == 5);
    assert!(test_reward::peek_amount(&rt) == 5);
    test_reward::skip(&mut rt);
    assert!(test_reward::peek_amount(&rt) == 100);
    let (_, _, amount) = test_reward::pay(&mut rt);
    assert!(amount == 100);
    core::finish(rt);
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun peek_reward_of_other_type_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(&mut s, AUTHOR, academy_id, vector[], vector[test_check_b::requirement()]);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let rt = core::complete(t, &mut quest);
    test_reward::peek_amount(&rt);
    abort
}

#[test, expected_failure(abort_code = core::ENoPendingRequirement)]
fun peek_reward_without_pending_fails() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    let quest_id = new_quest_with(&mut s, AUTHOR, academy_id, vector[], vector[]);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let rt = core::complete(t, &mut quest);
    test_reward::peek_amount(&rt);
    abort
}
