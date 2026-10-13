#[test_only]
module academy_arcade::arcade_tests;

use academy_arcade::arcade::{Self, AdminCap, Bank, Boards, ModeratorCap, OperatorCap, ResultSignerCap};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

public struct EVE has drop {}

const ADMIN: address = @0xAD;
const OWNER: address = @0x0E;
const SERVER: address = @0x5E;
const MOD: address = @0x30;
const PLAYER: address = @0xB1;
const DAY: u64 = 86_400_000;
const WEEK: u64 = 604_800_000;
const ANCHOR: u64 = 345_600_000;
const PRICE: u64 = 500_000_000;
const EVE_PRICE: u64 = 5_000_000_000;
const MAX_SCORE: u64 = 1_000_000;
const W: u64 = 2900;
const NONCE: vector<u8> = x"00112233445566778899aabbccddeeff";

fun at(week: u64, offset: u64): u64 { ANCHOR + week * WEEK + offset }

fun setup(s: &mut Scenario): Clock { setup_with_end(s, at(W + 8, 0)) }

fun setup_with_end(s: &mut Scenario, cycle_end_ms: u64): Clock {
    arcade::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(at(W, DAY));
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, cycle_end_ms, MAX_SCORE, &clock, s.ctx());
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(moderator, MOD);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    arcade::create_bank<SUI>(&admin, &mut boards, OWNER, PRICE, &clock, s.ctx());
    arcade::create_bank<EVE>(&admin, &mut boards, OWNER, EVE_PRICE, &clock, s.ctx());
    ts::return_shared(boards);
    s.return_to_sender(admin);
    clock
}

fun pay<T>(s: &mut Scenario, clock: &Clock, amount: u64) {
    s.next_tx(PLAYER);
    let mut bank = s.take_shared<Bank<T>>();
    let boards = s.take_shared<Boards>();
    arcade::pay_attempt(&mut bank, &boards, coin::mint_for_testing<T>(amount, s.ctx()), NONCE, clock, s.ctx());
    ts::return_shared(bank);
    ts::return_shared(boards);
}

fun banks<T>(s: &mut Scenario): vector<u64> {
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<T>>();
    let r = vector[bank.week_bank(), bank.closed_bank(), bank.cycle_bank()];
    ts::return_shared(bank);
    r
}

fun owner_got<T>(s: &mut Scenario): u64 {
    s.next_tx(OWNER);
    if (!ts::has_most_recent_for_sender<Coin<T>>(s)) return 0;
    let c = s.take_from_sender<Coin<T>>();
    let v = c.value();
    s.return_to_sender(c);
    v
}

#[test]
fun pay_attempt_splits_50_30_20_exactly() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    pay<SUI>(&mut s, &clock, PRICE);
    let fx = s.next_tx(ADMIN);
    assert!(fx.num_user_events() == 1);
    assert!(banks<SUI>(&mut s) == vector[250_000_000, 0, 150_000_000]);
    assert!(owner_got<SUI>(&mut s) == 100_000_000);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun split_remainder_goes_to_owner() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared<Bank<SUI>>();
    let admin = s.take_from_sender<AdminCap>();
    bank.set_price(&admin, 7);
    s.return_to_sender(admin);
    ts::return_shared(bank);
    pay<SUI>(&mut s, &clock, 7);
    assert!(banks<SUI>(&mut s) == vector[3, 0, 2]);
    assert!(owner_got<SUI>(&mut s) == 2);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun eve_bank_has_its_own_price_and_coin() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    pay<EVE>(&mut s, &clock, EVE_PRICE);
    assert!(banks<EVE>(&mut s) == vector[2_500_000_000, 0, 1_500_000_000]);
    assert!(banks<SUI>(&mut s) == vector[0, 0, 0]);
    assert!(owner_got<EVE>(&mut s) == 1_000_000_000);
    assert!(owner_got<SUI>(&mut s) == 0);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EWrongPrice)]
fun sui_price_in_eve_bank_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    pay<EVE>(&mut s, &clock, PRICE);
    abort
}

#[test, expected_failure(abort_code = arcade::EWrongPrice)]
fun pay_attempt_below_price_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    pay<SUI>(&mut s, &clock, PRICE - 1);
    abort
}

#[test, expected_failure(abort_code = arcade::EWrongPrice)]
fun pay_attempt_above_price_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    pay<SUI>(&mut s, &clock, PRICE + 1);
    abort
}

#[test, expected_failure(abort_code = arcade::ENonceLength)]
fun pay_attempt_bad_nonce_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(PLAYER);
    let mut bank = s.take_shared<Bank<SUI>>();
    let boards = s.take_shared<Boards>();
    arcade::pay_attempt(&mut bank, &boards, coin::mint_for_testing<SUI>(PRICE, s.ctx()), x"0011", &clock, s.ctx());
    abort
}

#[test, expected_failure(abort_code = arcade::ECycleEnded)]
fun pay_attempt_after_cycle_end_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 8, 0));
    pay<SUI>(&mut s, &clock, PRICE);
    abort
}

#[test]
fun pay_attempt_open_while_cycle_end_unset() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup_with_end(&mut s, 0);
    clock.set_for_testing(at(W + 52, DAY));
    pay<SUI>(&mut s, &clock, PRICE);
    s.next_tx(ADMIN);
    let boards = s.take_shared<Boards>();
    assert!(boards.cycle_end_ms() == 0);
    ts::return_shared(boards);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ECycleEnded)]
fun cycle_end_now_stops_payments() {
    let mut s = ts::begin(ADMIN);
    let clock = setup_with_end(&mut s, 0);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_cycle_end_now(&admin, &clock);
    assert!(boards.cycle_end_ms() == at(W, DAY));
    s.return_to_sender(admin);
    ts::return_shared(boards);
    pay<SUI>(&mut s, &clock, PRICE);
    abort
}

#[test, expected_failure(abort_code = arcade::EBadCycleEnd)]
fun cycle_end_in_past_rejected() {
    let mut s = ts::begin(ADMIN);
    let clock = setup_with_end(&mut s, 0);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_cycle_end_ms(&admin, at(W, DAY), &clock);
    abort
}

#[test]
fun fees_of_closed_week_roll_into_closed_bank() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    pay<SUI>(&mut s, &clock, PRICE);
    clock.set_for_testing(at(W + 1, 10));
    pay<SUI>(&mut s, &clock, PRICE);
    assert!(banks<SUI>(&mut s) == vector[250_000_000, 250_000_000, 300_000_000]);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun fund_cycle_adds_to_cycle_bank_of_that_coin() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(OWNER);
    let mut bank = s.take_shared<Bank<SUI>>();
    arcade::fund_cycle(&mut bank, coin::mint_for_testing<SUI>(100_000_000_000, s.ctx()), s.ctx());
    assert!(bank.cycle_bank() == 100_000_000_000);
    ts::return_shared(bank);
    assert!(banks<EVE>(&mut s) == vector[0, 0, 0]);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EPaused)]
fun paused_boards_block_every_currency() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_paused(&admin, true);
    s.return_to_sender(admin);
    ts::return_shared(boards);
    pay<EVE>(&mut s, &clock, EVE_PRICE);
    abort
}

#[test, expected_failure(abort_code = arcade::EPaused)]
fun paused_bank_blocks_only_its_currency() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared<Bank<EVE>>();
    let admin = s.take_from_sender<AdminCap>();
    bank.set_bank_paused(&admin, true);
    s.return_to_sender(admin);
    ts::return_shared(bank);
    pay<SUI>(&mut s, &clock, PRICE);
    pay<EVE>(&mut s, &clock, EVE_PRICE);
    abort
}

#[test]
fun sui_pays_while_eve_bank_paused() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared<Bank<EVE>>();
    let admin = s.take_from_sender<AdminCap>();
    bank.set_bank_paused(&admin, true);
    s.return_to_sender(admin);
    ts::return_shared(bank);
    pay<SUI>(&mut s, &clock, PRICE);
    assert!(banks<SUI>(&mut s) == vector[250_000_000, 0, 150_000_000]);
    assert!(owner_got<SUI>(&mut s) == 100_000_000);
    assert!(banks<EVE>(&mut s) == vector[0, 0, 0]);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EBankExists)]
fun one_bank_per_coin_type() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    arcade::create_bank<SUI>(&admin, &mut boards, OWNER, PRICE, &clock, s.ctx());
    abort
}

#[test, expected_failure(abort_code = arcade::EWrongBoards)]
fun bank_of_other_boards_rejected() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let old_id = ts::most_recent_id_shared<Boards>().destroy_some();
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, at(W + 16, 0), MAX_SCORE, &clock, s.ctx());
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(moderator, MOD);
    s.return_to_sender(admin);
    s.next_tx(PLAYER);
    let new_id = ts::most_recent_id_shared<Boards>().destroy_some();
    assert!(new_id != old_id);
    let mut bank = s.take_shared<Bank<SUI>>();
    let boards = s.take_shared_by_id<Boards>(new_id);
    arcade::pay_attempt(&mut bank, &boards, coin::mint_for_testing<SUI>(PRICE, s.ctx()), NONCE, &clock, s.ctx());
    abort
}

#[test]
fun boards_register_bank_of_each_currency() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let boards = s.take_shared<Boards>();
    let sui_bank = s.take_shared<Bank<SUI>>();
    let eve_bank = s.take_shared<Bank<EVE>>();
    assert!(boards.has_bank<SUI>() && boards.has_bank<EVE>());
    assert!(boards.bank_of<SUI>() == object::id(&sui_bank));
    assert!(boards.bank_of<EVE>() == object::id(&eve_bank));
    assert!(sui_bank.boards_id() == object::id(&boards));
    ts::return_shared(boards);
    ts::return_shared(sui_bank);
    ts::return_shared(eve_bank);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun admin_changes_price_and_split_of_one_bank() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared<Bank<SUI>>();
    let admin = s.take_from_sender<AdminCap>();
    bank.set_price(&admin, 1_000_000_000);
    bank.set_split_bps(&admin, vector[6000, 3000, 1000]);
    s.return_to_sender(admin);
    ts::return_shared(bank);
    pay<SUI>(&mut s, &clock, 1_000_000_000);
    assert!(banks<SUI>(&mut s) == vector[600_000_000, 0, 300_000_000]);
    pay<EVE>(&mut s, &clock, EVE_PRICE);
    assert!(banks<EVE>(&mut s) == vector[2_500_000_000, 0, 1_500_000_000]);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EBadSplit)]
fun split_must_sum_to_10000() {
    let mut s = ts::begin(ADMIN);
    let _clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared<Bank<SUI>>();
    let admin = s.take_from_sender<AdminCap>();
    bank.set_split_bps(&admin, vector[5000, 3000, 1999]);
    abort
}

#[test, expected_failure(abort_code = arcade::EBadShares)]
fun shares_must_sum_to_10000() {
    let mut s = ts::begin(ADMIN);
    let _clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared<Bank<EVE>>();
    let admin = s.take_from_sender<AdminCap>();
    bank.set_payout_shares(&admin, vector[5000, 3000, 2000], vector[4000, 2500, 1500, 1200, 799]);
    abort
}

#[test, expected_failure(abort_code = arcade::EBadDelay)]
fun review_delay_bounds() {
    let mut s = ts::begin(ADMIN);
    let _clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_review_delay_ms(&admin, 3_599_999);
    abort
}

#[test, expected_failure(abort_code = arcade::EBadLeague)]
fun league_points_capped_at_board_size() {
    let mut s = ts::begin(ADMIN);
    let _clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_league_points(&admin, vector[10, 7, 5, 3, 3, 3, 3, 3, 3, 3], 1);
    boards.set_league_points(&admin, vector[10, 7, 5, 3, 3, 3, 3, 3, 3, 3, 1], 1);
    abort
}

#[test]
fun rotation_replaces_cap_ids() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    let old_op = boards.operator_cap_id();
    let op = boards.rotate_operator(&admin, s.ctx());
    assert!(boards.operator_cap_id() == object::id(&op) && old_op != object::id(&op));
    let signer = boards.rotate_signer(&admin, s.ctx());
    assert!(boards.signer_cap_id() == object::id(&signer));
    let m = boards.mint_moderator(&admin, s.ctx());
    assert!(boards.is_moderator(object::id(&m)));
    boards.revoke_moderator(&admin, object::id(&m));
    assert!(!boards.is_moderator(object::id(&m)));
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(m, MOD);
    s.return_to_sender(admin);
    ts::return_shared(boards);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun create_gives_caps_to_their_holders() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(SERVER);
    assert!(ts::has_most_recent_for_sender<OperatorCap>(&s));
    assert!(ts::has_most_recent_for_sender<ResultSignerCap>(&s));
    s.next_tx(MOD);
    assert!(ts::has_most_recent_for_sender<ModeratorCap>(&s));
    clock.destroy_for_testing();
    s.end();
}
