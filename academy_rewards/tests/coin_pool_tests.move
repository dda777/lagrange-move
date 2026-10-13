#[test_only]
module academy_rewards::coin_pool_tests;

use academy_core::core::{Self, Academy, AcademyAdminCap, Quest, Requirement, RewardTicket};
use academy_rewards::{badge::{Self, Badge}, coin_pool::{Self, CoinPool}, test_identity};
use std::string::{String, utf8};
use sui::{clock, coin::{Self, Coin}, event, test_scenario::{Self as ts, Scenario}};

const AUTHOR: address = @0xA1;
const OTHER_AUTHOR: address = @0xA2;
const FUNDER: address = @0xF1;
const PLAYER: address = @0xB1;
const PLAYER_2: address = @0xB2;
const IMAGE: vector<u8> = b"https://example.org/pool.png";

public struct TEST_COIN has drop {}

public struct OTHER_COIN has drop {}

fun tenant(): String { utf8(b"TEST") }

fun new_academy(s: &mut Scenario, author: address): ID {
    s.next_tx(author);
    let cap = core::create_academy(utf8(b"A"), utf8(b""), x"", s.ctx());
    let academy_id = cap.admin_academy_id();
    transfer::public_transfer(cap, author);
    academy_id
}

fun new_pool<T>(s: &mut Scenario, author: address, max_claims: u64, funded: u64): ID {
    s.next_tx(author);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let pool_id = coin_pool::create<T>(&cap, max_claims, s.ctx());
    s.return_to_sender(cap);
    if (funded > 0) {
        s.next_tx(FUNDER);
        let mut pool = s.take_shared_by_id<CoinPool<T>>(pool_id);
        pool.fund(coin::mint_for_testing<T>(funded, s.ctx()), s.ctx());
        ts::return_shared(pool);
    };
    pool_id
}

fun coin_req<T>(s: &mut Scenario, author: address, pool_id: ID, amount: u64, optional: bool): Requirement {
    s.next_tx(author);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let pool = s.take_shared_by_id<CoinPool<T>>(pool_id);
    let req = coin_pool::requirement(&pool, &cap, amount, optional);
    ts::return_shared(pool);
    s.return_to_sender(cap);
    req
}

fun new_quest(s: &mut Scenario, author: address, academy_id: ID, rewards: vector<Requirement>): ID {
    s.next_tx(author);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let quest_id = core::create_quest(
        &mut academy,
        &cap,
        test_identity::requirement(),
        vector[],
        rewards,
        utf8(b""),
        x"",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    quest_id
}

fun start_claim(quest: &mut Quest, player: address, game_id: u64): RewardTicket {
    let mut t = core::begin_claim(quest);
    test_identity::bind(&mut t, tenant(), game_id, player);
    core::complete(t, quest)
}

fun claim_badge_and_coins<T>(s: &mut Scenario, quest_id: ID, pool_id: ID, player: address, game_id: u64) {
    s.next_tx(player);
    let clock = clock::create_for_testing(s.ctx());
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut pool = s.take_shared_by_id<CoinPool<T>>(pool_id);
    let mut rt = start_claim(&mut quest, player, game_id);
    badge::issue(&mut rt, &clock, s.ctx());
    coin_pool::pay(&mut rt, &mut pool, s.ctx());
    core::finish(rt);
    ts::return_shared(pool);
    ts::return_shared(quest);
    clock.destroy_for_testing();
}

fun setup(s: &mut Scenario, max_claims: u64, funded: u64, optional: bool): (ID, ID) {
    let academy_id = new_academy(s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(s, AUTHOR, max_claims, funded);
    let coin = coin_req<TEST_COIN>(s, AUTHOR, pool_id, 10, optional);
    let quest_id = new_quest(s, AUTHOR, academy_id, vector[badge::requirement(utf8(IMAGE)), coin]);
    (quest_id, pool_id)
}

fun pool_state(s: &mut Scenario, pool_id: ID): (u64, u64) {
    let pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    let (value, claims) = (pool.value(), pool.claims());
    ts::return_shared(pool);
    (value, claims)
}

#[test]
fun admin_creates_pool_and_anyone_funds_it() {
    let mut s = ts::begin(AUTHOR);
    let academy_id = new_academy(&mut s, AUTHOR);
    s.next_tx(AUTHOR);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let pool_id = coin_pool::create<TEST_COIN>(&cap, 5, s.ctx());
    assert!(event::events_by_type<coin_pool::PoolCreated>().length() == 1);
    s.return_to_sender(cap);

    s.next_tx(FUNDER);
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    assert!(pool.academy_id() == academy_id);
    assert!(pool.max_claims() == 5);
    assert!(pool.claims() == 0);
    assert!(pool.value() == 0);
    pool.fund(coin::mint_for_testing<TEST_COIN>(70, s.ctx()), s.ctx());
    pool.fund(coin::mint_for_testing<TEST_COIN>(30, s.ctx()), s.ctx());
    assert!(event::events_by_type<coin_pool::PoolFunded>().length() == 2);
    assert!(pool.value() == 100);
    ts::return_shared(pool);
    s.end();
}

#[test, expected_failure(abort_code = coin_pool::EZeroAmount)]
fun fund_with_zero_coin_fails() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 0);
    s.next_tx(FUNDER);
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    pool.fund(coin::zero<TEST_COIN>(s.ctx()), s.ctx());
    abort
}

#[test]
fun admin_withdraws_remainder() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 100);
    s.next_tx(AUTHOR);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    let part = pool.withdraw(&cap, 40, s.ctx());
    assert!(part.value() == 40);
    assert!(pool.value() == 60);
    let rest_amount = pool.value();
    let rest = pool.withdraw(&cap, rest_amount, s.ctx());
    assert!(rest.value() == 60);
    assert!(pool.value() == 0);
    assert!(event::events_by_type<coin_pool::PoolWithdrawn>().length() == 2);
    coin::burn_for_testing(part);
    coin::burn_for_testing(rest);
    ts::return_shared(pool);
    s.return_to_sender(cap);
    s.end();
}

#[test, expected_failure(abort_code = coin_pool::ENotAcademyAdmin)]
fun admin_of_other_academy_cannot_withdraw() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    new_academy(&mut s, OTHER_AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 100);
    s.next_tx(OTHER_AUTHOR);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    let stolen = pool.withdraw(&cap, 100, s.ctx());
    coin::burn_for_testing(stolen);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EWithdrawExceedsBalance)]
fun withdraw_more_than_balance_fails() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 100);
    s.next_tx(AUTHOR);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    let c = pool.withdraw(&cap, 101, s.ctx());
    coin::burn_for_testing(c);
    abort
}

#[test, expected_failure(abort_code = coin_pool::ENotAcademyAdmin)]
fun requirement_for_pool_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    new_academy(&mut s, OTHER_AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 100);
    coin_req<TEST_COIN>(&mut s, OTHER_AUTHOR, pool_id, 10, false);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EZeroAmount)]
fun requirement_with_zero_amount_fails() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 100);
    coin_req<TEST_COIN>(&mut s, AUTHOR, pool_id, 0, false);
    abort
}

#[test]
fun reward_config_getters_decode_bcs() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 100);
    let req = coin_req<TEST_COIN>(&mut s, AUTHOR, pool_id, 10, true);
    let mut r = sui::bcs::new(req.requirement_data());
    assert!(r.peel_address() == pool_id.to_address());
    assert!(r.peel_u64() == 10);
    assert!(r.peel_bool());
    assert!(
        req.requirement_type() == std::type_name::with_original_ids<coin_pool::CoinReward<TEST_COIN>>(),
    );
    s.end();
}

#[test]
fun claim_pays_badge_and_coins() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 100, false);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    let effects = s.next_tx(PLAYER);
    assert!(effects.num_user_events() == 3);
    let paid = s.take_from_sender<Coin<TEST_COIN>>();
    assert!(paid.value() == 10);
    s.return_to_sender(paid);
    let b = s.take_from_sender<Badge>();
    s.return_to_sender(b);
    let (value, claims) = pool_state(&mut s, pool_id);
    assert!(value == 90);
    assert!(claims == 1);
    s.end();
}

#[test]
fun pool_can_serve_several_quests_of_its_academy() {
    let mut s = ts::begin(AUTHOR);
    let (quest_a, pool_id) = setup(&mut s, 0, 100, false);
    let academy_id = {
        s.next_tx(AUTHOR);
        let q = s.take_shared_by_id<Quest>(quest_a);
        let id = q.academy_id();
        ts::return_shared(q);
        id
    };
    let coin = coin_req<TEST_COIN>(&mut s, AUTHOR, pool_id, 10, false);
    let quest_b = new_quest(&mut s, AUTHOR, academy_id, vector[badge::requirement(utf8(IMAGE)), coin]);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_a, pool_id, PLAYER, 101);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_b, pool_id, PLAYER, 101);
    s.next_tx(PLAYER);
    let (value, claims) = pool_state(&mut s, pool_id);
    assert!(value == 80);
    assert!(claims == 2);
    s.end();
}

#[test, expected_failure(abort_code = coin_pool::EWrongPool)]
fun paying_from_other_pool_of_same_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, _pool_id) = setup(&mut s, 0, 100, false);
    let other_pool = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 100);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, other_pool, PLAYER, 101);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EWrongPool)]
fun wrong_pool_aborts_even_if_optional() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, _pool_id) = setup(&mut s, 0, 100, true);
    let other_pool = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 0);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, other_pool, PLAYER, 101);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EWrongAcademy)]
fun quest_of_other_academy_cannot_drain_pool_with_copied_requirement() {
    let mut s = ts::begin(AUTHOR);
    let (quest_a, pool_id) = setup(&mut s, 0, 100, false);
    let other_academy = new_academy(&mut s, OTHER_AUTHOR);
    s.next_tx(OTHER_AUTHOR);
    let qa = s.take_shared_by_id<Quest>(quest_a);
    let copied = qa.rewards()[1];
    ts::return_shared(qa);
    let quest_b = new_quest(&mut s, OTHER_AUTHOR, other_academy, vector[badge::requirement(utf8(IMAGE)), copied]);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_b, pool_id, PLAYER, 101);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EWrongAcademy)]
fun copied_optional_requirement_of_other_academy_also_aborts() {
    let mut s = ts::begin(AUTHOR);
    let (quest_a, pool_id) = setup(&mut s, 0, 100, true);
    let other_academy = new_academy(&mut s, OTHER_AUTHOR);
    s.next_tx(OTHER_AUTHOR);
    let qa = s.take_shared_by_id<Quest>(quest_a);
    let copied = qa.rewards()[1];
    ts::return_shared(qa);
    let quest_b = new_quest(&mut s, OTHER_AUTHOR, other_academy, vector[badge::requirement(utf8(IMAGE)), copied]);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_b, pool_id, PLAYER, 101);
    abort
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun pool_of_other_coin_type_fails() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, _pool_id) = setup(&mut s, 0, 100, false);
    let other_coin_pool = new_pool<OTHER_COIN>(&mut s, AUTHOR, 0, 100);
    claim_badge_and_coins<OTHER_COIN>(&mut s, quest_id, other_coin_pool, PLAYER, 101);
    abort
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun pay_out_of_order_fails() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 100, false);
    s.next_tx(PLAYER);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    let mut rt = start_claim(&mut quest, PLAYER, 101);
    coin_pool::pay(&mut rt, &mut pool, s.ctx());
    abort
}

#[test, expected_failure(abort_code = coin_pool::EMaxClaimsReached)]
fun max_claims_reached_aborts_required_reward() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 1, 100, false);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER_2, 102);
    abort
}

#[test]
fun max_claims_reached_skips_optional_reward_badge_still_issued() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 1, 100, true);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER_2, 102);
    assert!(event::events_by_type<coin_pool::RewardSkipped>().length() == 1);
    let effects = s.next_tx(PLAYER_2);
    assert!(effects.num_user_events() == 3);
    assert!(s.has_most_recent_for_sender<Badge>());
    assert!(!s.has_most_recent_for_sender<Coin<TEST_COIN>>());
    let (value, claims) = pool_state(&mut s, pool_id);
    assert!(value == 90);
    assert!(claims == 1);
    s.end();
}

#[test]
fun zero_max_claims_means_unlimited() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 100, false);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER_2, 102);
    s.next_tx(PLAYER);
    let (value, claims) = pool_state(&mut s, pool_id);
    assert!(value == 80);
    assert!(claims == 2);
    s.end();
}

#[test, expected_failure(abort_code = coin_pool::EPoolInsufficient)]
fun empty_pool_aborts_required_reward() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 0, false);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EPoolInsufficient)]
fun insufficient_pool_aborts_required_reward() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 9, false);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    abort
}

#[test]
fun empty_pool_skips_optional_reward_badge_still_issued() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 0, true);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    let effects = s.next_tx(PLAYER);
    assert!(effects.num_user_events() == 3);
    assert!(s.has_most_recent_for_sender<Badge>());
    assert!(!s.has_most_recent_for_sender<Coin<TEST_COIN>>());
    let (value, claims) = pool_state(&mut s, pool_id);
    assert!(value == 0);
    assert!(claims == 0);
    s.end();
}

#[test]
fun insufficient_pool_skips_optional_reward_and_keeps_balance() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 9, true);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    s.next_tx(PLAYER);
    assert!(!s.has_most_recent_for_sender<Coin<TEST_COIN>>());
    let (value, claims) = pool_state(&mut s, pool_id);
    assert!(value == 9);
    assert!(claims == 0);
    s.end();
}

#[test]
fun optional_reward_paid_when_pool_has_funds() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 100, true);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    s.next_tx(PLAYER);
    let paid = s.take_from_sender<Coin<TEST_COIN>>();
    assert!(paid.value() == 10);
    s.return_to_sender(paid);
    s.end();
}

#[test]
fun refunded_pool_pays_again() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 0, true);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    s.next_tx(FUNDER);
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    pool.fund(coin::mint_for_testing<TEST_COIN>(10, s.ctx()), s.ctx());
    ts::return_shared(pool);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER_2, 102);
    s.next_tx(PLAYER_2);
    let paid = s.take_from_sender<Coin<TEST_COIN>>();
    assert!(paid.value() == 10);
    s.return_to_sender(paid);
    s.end();
}

fun break_version(s: &mut Scenario, pool_id: ID) {
    s.next_tx(AUTHOR);
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    pool.set_version_for_testing(999);
    ts::return_shared(pool);
}

#[test, expected_failure(abort_code = coin_pool::EWrongVersion)]
fun fund_pool_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 0);
    break_version(&mut s, pool_id);
    s.next_tx(FUNDER);
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    pool.fund(coin::mint_for_testing<TEST_COIN>(1, s.ctx()), s.ctx());
    abort
}

#[test, expected_failure(abort_code = coin_pool::EWrongVersion)]
fun withdraw_from_pool_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 10);
    break_version(&mut s, pool_id);
    s.next_tx(AUTHOR);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    let c = pool.withdraw(&cap, 1, s.ctx());
    coin::burn_for_testing(c);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EWrongVersion)]
fun requirement_for_pool_with_wrong_version_fails() {
    let mut s = ts::begin(AUTHOR);
    new_academy(&mut s, AUTHOR);
    let pool_id = new_pool<TEST_COIN>(&mut s, AUTHOR, 0, 10);
    break_version(&mut s, pool_id);
    coin_req<TEST_COIN>(&mut s, AUTHOR, pool_id, 1, false);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EWrongVersion)]
fun pay_from_pool_with_wrong_version_fails_even_if_optional() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 100, true);
    break_version(&mut s, pool_id);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    abort
}

fun make_old(s: &mut Scenario, pool_id: ID) {
    s.next_tx(AUTHOR);
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    pool.set_version_for_testing(coin_pool::package_version() - 1);
    ts::return_shared(pool);
}

fun migrate_pool(s: &mut Scenario, author: address, pool_id: ID) {
    s.next_tx(author);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let mut pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    pool.migrate(&cap);
    ts::return_shared(pool);
    s.return_to_sender(cap);
}

#[test, expected_failure(abort_code = coin_pool::EWrongVersion)]
fun old_pool_is_blocked_before_migrate() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 100, false);
    make_old(&mut s, pool_id);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    abort
}

#[test]
fun old_pool_works_after_migrate() {
    let mut s = ts::begin(AUTHOR);
    let (quest_id, pool_id) = setup(&mut s, 0, 100, false);
    make_old(&mut s, pool_id);
    migrate_pool(&mut s, AUTHOR, pool_id);
    s.next_tx(AUTHOR);
    let pool = s.take_shared_by_id<CoinPool<TEST_COIN>>(pool_id);
    assert!(pool.version() == coin_pool::package_version());
    assert!(pool.value() == 100 && pool.claims() == 0);
    ts::return_shared(pool);
    claim_badge_and_coins<TEST_COIN>(&mut s, quest_id, pool_id, PLAYER, 101);
    s.next_tx(AUTHOR);
    let (value, claims) = pool_state(&mut s, pool_id);
    assert!(value == 90 && claims == 1);
    s.end();
}

#[test, expected_failure(abort_code = coin_pool::EAlreadyMigrated)]
fun migrate_current_pool_fails() {
    let mut s = ts::begin(AUTHOR);
    let (_quest_id, pool_id) = setup(&mut s, 0, 0, false);
    migrate_pool(&mut s, AUTHOR, pool_id);
    abort
}

#[test, expected_failure(abort_code = coin_pool::EAlreadyMigrated)]
fun migrate_newer_pool_fails() {
    let mut s = ts::begin(AUTHOR);
    let (_quest_id, pool_id) = setup(&mut s, 0, 0, false);
    break_version(&mut s, pool_id);
    migrate_pool(&mut s, AUTHOR, pool_id);
    abort
}

#[test, expected_failure(abort_code = coin_pool::ENotAcademyAdmin)]
fun migrate_by_admin_of_other_academy_fails() {
    let mut s = ts::begin(AUTHOR);
    let (_quest_id, pool_id) = setup(&mut s, 0, 0, false);
    make_old(&mut s, pool_id);
    new_academy(&mut s, OTHER_AUTHOR);
    migrate_pool(&mut s, OTHER_AUTHOR, pool_id);
    abort
}
