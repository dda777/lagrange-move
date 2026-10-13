#[test_only]
module academy_triex_v0::triex_v0_tests;

use academy_core::core::{Self, Academy, AcademyAdminCap, ClaimTicket, Quest, Requirement};
use academy_triex_v0::triex_v0;
use std::{internal, string::utf8};
use sui::test_scenario::{Self as ts, Scenario};
use token::cred::CRED;
use triex::trading_account::{Self, TradingAccount};

const AUTHOR: address = @0xA1;
const PLAYER: address = @0xB1;
const OTHER: address = @0xB2;
const TRADED: u128 = 1_343_330_250_200;

public struct OTHER_CHECK has drop {}

public struct TestIdentity() has drop;

fun bind(t: &mut ClaimTicket, game_id: u64, recipient: address) {
    t.bind_player(internal::permit<TestIdentity>(), utf8(b"TEST"), game_id, recipient);
}

fun create_quest(s: &mut Scenario, checks: vector<Requirement>): ID {
    s.next_tx(AUTHOR);
    let cap = core::create_academy(utf8(b"Academy"), utf8(b""), x"", s.ctx());
    let academy_id = cap.admin_academy_id();
    transfer::public_transfer(cap, AUTHOR);
    s.next_tx(AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let quest_id = core::create_quest(
        &mut academy,
        &cap,
        core::requirement(TestIdentity()),
        checks,
        vector[],
        utf8(b"ipfs://quest"),
        x"",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    quest_id
}

fun new_account(s: &mut Scenario, owner: address): ID {
    s.next_tx(owner);
    let account = trading_account::new(s.ctx());
    let id = trading_account::id(&account);
    transfer::public_share_object(account);
    id
}

fun claim(
    s: &mut Scenario,
    quest_id: ID,
    account_id: ID,
    sender: address,
    recipient: address,
    game_id: u64,
    checks: u64,
    turnover: Option<u128>,
) {
    s.next_tx(sender);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let account = s.take_shared_by_id<TradingAccount>(account_id);
    let mut t = core::begin_claim(&quest);
    bind(&mut t, game_id, recipient);
    checks.do!(|_| {
        if (turnover.is_some()) {
            triex_v0::check_triex_trade_with_turnover_for_testing(&mut t, &account, *turnover.borrow(), s.ctx())
        } else {
            triex_v0::check_triex_trade<CRED>(&mut t, &account, s.ctx())
        }
    });
    let rt = core::complete(t, &mut quest);
    core::finish(rt);
    ts::return_shared(account);
    ts::return_shared(quest);
}

#[test]
fun trade_on_own_account_passes_and_burns_account_as_evidence() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 1, option::some(TRADED));

    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.claims() == 1);
    assert!(quest.is_evidence_used(account_id));
    assert!(quest.has_wallet_claimed(PLAYER));
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = triex_v0::ENoTrades)]
fun fresh_account_without_trades_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 1, option::none());
    s.end();
}

#[test, expected_failure(abort_code = triex_v0::ENoTrades)]
fun zero_turnover_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 1, option::some(0));
    s.end();
}

#[test, expected_failure(abort_code = triex_v0::ENotAccountOwner)]
fun foreign_account_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, OTHER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 1, option::none());
    s.end();
}

#[test, expected_failure(abort_code = triex_v0::ENotAccountOwner)]
fun foreign_account_with_trades_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, OTHER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 1, option::some(TRADED));
    s.end();
}

#[test, expected_failure(abort_code = triex_v0::ENotAccountOwner)]
fun account_of_sender_but_other_recipient_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, PLAYER, OTHER, 1, 1, option::some(TRADED));
    s.end();
}

#[test, expected_failure(abort_code = triex_v0::ENotAccountOwner)]
fun account_of_recipient_sent_by_other_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, OTHER, PLAYER, 1, 1, option::some(TRADED));
    s.end();
}

#[test, expected_failure(abort_code = core::EEvidenceUsed)]
fun same_account_twice_in_quest_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade(), triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 2, option::some(TRADED));
    s.end();
}

#[test, expected_failure(abort_code = core::EAlreadyClaimedByWallet)]
fun second_claim_of_same_wallet_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 1, option::some(TRADED));
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 2, 1, option::some(TRADED));
    s.end();
}

#[test, expected_failure(abort_code = core::ENoIdentity)]
fun check_before_bind_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[triex_v0::triex_trade()]);
    let account_id = new_account(&mut s, PLAYER);
    s.next_tx(PLAYER);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let account = s.take_shared_by_id<TradingAccount>(account_id);
    let mut t = core::begin_claim(&quest);
    triex_v0::check_triex_trade<CRED>(&mut t, &account, s.ctx());
    abort 0
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun other_requirement_type_fails() {
    let mut s = ts::begin(AUTHOR);
    let quest_id = create_quest(&mut s, vector[core::requirement(OTHER_CHECK {})]);
    let account_id = new_account(&mut s, PLAYER);
    claim(&mut s, quest_id, account_id, PLAYER, PLAYER, 1, 1, option::some(TRADED));
    s.end();
}
