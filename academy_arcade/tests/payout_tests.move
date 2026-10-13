#[test_only]
module academy_arcade::payout_tests;

use academy_arcade::arcade::{Self, AdminCap, Bank, Boards, OperatorCap, ResultSignerCap};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

public struct EVE has drop {}

const ADMIN: address = @0xAD;
const OWNER: address = @0x0E;
const SERVER: address = @0x5E;
const MOD: address = @0x30;
const PAYER: address = @0xF0;
const HOUR: u64 = 3_600_000;
const DAY: u64 = 86_400_000;
const WEEK: u64 = 604_800_000;
const ANCHOR: u64 = 345_600_000;
const PRICE: u64 = 500_000_000;
const EVE_PRICE: u64 = 5_000_000_000;
const W: u64 = 2900;
const HASH: vector<u8> = x"abababababababababababababababababababababababababababababababab";
const NONCE: vector<u8> = x"00112233445566778899aabbccddeeff";

fun at(week: u64, offset: u64): u64 { ANCHOR + week * WEEK + offset }

fun player(n: u64): address { sui::address::from_u256((0xB000 + n) as u256) }

fun setup(s: &mut Scenario, cycle_weeks: u64): Clock {
    arcade::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(at(W, DAY));
    let admin = s.take_from_sender<AdminCap>();
    let end = if (cycle_weeks == 0) 0 else at(W + cycle_weeks, 0);
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, end, 1_000_000, &clock, s.ctx());
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

fun pay_n<T>(s: &mut Scenario, clock: &Clock, price: u64, n: u64) {
    let mut i = 0;
    while (i < n) {
        s.next_tx(PAYER);
        let mut bank = s.take_shared<Bank<T>>();
        let boards = s.take_shared<Boards>();
        arcade::pay_attempt(&mut bank, &boards, coin::mint_for_testing<T>(price, s.ctx()), NONCE, clock, s.ctx());
        ts::return_shared(bank);
        ts::return_shared(boards);
        i = i + 1;
    }
}

fun record(s: &mut Scenario, clock: &Clock, week: u64, who: address, score: u64) {
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<ResultSignerCap>();
    boards.record_result(&cap, week, who, object::id_from_address(who), score, HASH, clock, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(boards);
}

fun finalize(s: &mut Scenario, clock: &Clock, week: u64) {
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.finalize_week(&cap, week, clock, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(boards);
}

fun payout<T>(s: &mut Scenario, clock: &Clock, week: u64) {
    s.next_tx(SERVER);
    let mut bank = s.take_shared<Bank<T>>();
    let boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    arcade::payout_week(&mut bank, &boards, &cap, week, clock, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(bank);
    ts::return_shared(boards);
}

fun received<T>(s: &mut Scenario, who: address): u64 {
    s.next_tx(who);
    if (!ts::has_most_recent_for_sender<Coin<T>>(s)) return 0;
    let c = s.take_from_sender<Coin<T>>();
    let v = c.value();
    s.return_to_sender(c);
    v
}

fun closed<T>(s: &mut Scenario): u64 {
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<T>>();
    let v = bank.closed_bank();
    ts::return_shared(bank);
    v
}

fun admin_pause(s: &mut Scenario, boards_wide: bool) {
    s.next_tx(ADMIN);
    let admin = s.take_from_sender<AdminCap>();
    if (boards_wide) {
        let mut boards = s.take_shared<Boards>();
        boards.set_paused(&admin, true);
        ts::return_shared(boards);
    } else {
        let mut bank = s.take_shared<Bank<EVE>>();
        bank.set_bank_paused(&admin, true);
        ts::return_shared(bank);
    };
    s.return_to_sender(admin);
}

#[test]
fun payout_week_pays_top3_50_30_20_from_closed_bank() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    pay_n<SUI>(&mut s, &clock, PRICE, 4);
    record(&mut s, &clock, W, player(1), 900);
    record(&mut s, &clock, W, player(2), 800);
    record(&mut s, &clock, W, player(3), 700);
    record(&mut s, &clock, W, player(4), 600);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    assert!(received<SUI>(&mut s, player(2)) == 300_000_000);
    assert!(received<SUI>(&mut s, player(3)) == 200_000_000);
    assert!(received<SUI>(&mut s, player(4)) == 0);
    assert!(closed<SUI>(&mut s) == 0);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun each_bank_pays_its_own_coin_once() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    pay_n<SUI>(&mut s, &clock, PRICE, 4);
    pay_n<EVE>(&mut s, &clock, EVE_PRICE, 2);
    record(&mut s, &clock, W, player(1), 900);
    record(&mut s, &clock, W, player(2), 800);
    record(&mut s, &clock, W, player(3), 700);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<EVE>(&mut s, player(1)) == 0);
    s.next_tx(ADMIN);
    let eve_before = s.take_shared<Bank<EVE>>();
    assert!(!eve_before.is_week_paid(W) && eve_before.week_bank() == 5_000_000_000);
    ts::return_shared(eve_before);
    payout<EVE>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    assert!(received<EVE>(&mut s, player(1)) == 2_500_000_000);
    assert!(received<EVE>(&mut s, player(2)) == 1_500_000_000);
    assert!(received<EVE>(&mut s, player(3)) == 1_000_000_000);
    assert!(closed<SUI>(&mut s) == 0 && closed<EVE>(&mut s) == 0);
    s.next_tx(ADMIN);
    let sui_bank = s.take_shared<Bank<SUI>>();
    let eve_bank = s.take_shared<Bank<EVE>>();
    assert!(sui_bank.is_week_paid(W) && eve_bank.is_week_paid(W));
    ts::return_shared(sui_bank);
    ts::return_shared(eve_bank);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun fewer_than_three_winners_leave_rest_in_bank() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    pay_n<SUI>(&mut s, &clock, PRICE, 4);
    record(&mut s, &clock, W, player(1), 900);
    record(&mut s, &clock, W, player(2), 800);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    assert!(received<SUI>(&mut s, player(2)) == 300_000_000);
    assert!(closed<SUI>(&mut s) == 200_000_000);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun payout_amounts_never_exceed_bank() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared<Bank<SUI>>();
    let admin = s.take_from_sender<AdminCap>();
    bank.set_price(&admin, 1_999_999_998);
    s.return_to_sender(admin);
    ts::return_shared(bank);
    pay_n<SUI>(&mut s, &clock, 1_999_999_998, 1);
    record(&mut s, &clock, W, player(1), 3);
    record(&mut s, &clock, W, player(2), 2);
    record(&mut s, &clock, W, player(3), 1);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    let paid = received<SUI>(&mut s, player(1)) + received<SUI>(&mut s, player(2)) + received<SUI>(&mut s, player(3));
    assert!(paid <= 999_999_999);
    assert!(paid + closed<SUI>(&mut s) == 999_999_999);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EAlreadyPaid)]
fun payout_week_twice_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    abort
}

#[test, expected_failure(abort_code = arcade::ENotFinalized)]
fun payout_before_finalize_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    record(&mut s, &clock, W, player(1), 1);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    payout<SUI>(&mut s, &clock, W);
    abort
}

#[test, expected_failure(abort_code = arcade::EPaused)]
fun paused_boards_block_payouts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    admin_pause(&mut s, true);
    payout<SUI>(&mut s, &clock, W);
    abort
}

#[test, expected_failure(abort_code = arcade::EPaused)]
fun paused_bank_blocks_only_its_payout() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    admin_pause(&mut s, false);
    payout<SUI>(&mut s, &clock, W);
    payout<EVE>(&mut s, &clock, W);
    abort
}

#[test, expected_failure(abort_code = arcade::ENotOperator)]
fun rotated_operator_cannot_pay() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    let fresh = boards.rotate_operator(&admin, s.ctx());
    transfer::public_transfer(fresh, ADMIN);
    s.return_to_sender(admin);
    ts::return_shared(boards);
    payout<SUI>(&mut s, &clock, W);
    abort
}

#[test]
fun cycle_payout_by_league_points_after_end_and_scan() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 2);
    s.next_tx(OWNER);
    let mut bank = s.take_shared<Bank<SUI>>();
    arcade::fund_cycle(&mut bank, coin::mint_for_testing<SUI>(100_000_000_000, s.ctx()), s.ctx());
    ts::return_shared(bank);
    pay_n<EVE>(&mut s, &clock, EVE_PRICE, 10);
    record(&mut s, &clock, W, player(1), 900);
    record(&mut s, &clock, W, player(2), 800);
    record(&mut s, &clock, W, player(3), 700);
    clock.set_for_testing(at(W + 1, 25 * HOUR));
    finalize(&mut s, &clock, W);
    record(&mut s, &clock, W + 1, player(2), 990);
    record(&mut s, &clock, W + 1, player(1), 100);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    finalize(&mut s, &clock, W + 1);
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 2, &clock);
    assert!(!boards.scan_done());
    boards.scan_cycle(&cap, 2, &clock);
    assert!(boards.scan_done());
    assert!(boards.scan_top() == vector[player(2), player(1), player(3)]);
    let mut sui_bank = s.take_shared<Bank<SUI>>();
    let mut eve_bank = s.take_shared<Bank<EVE>>();
    arcade::payout_cycle(&mut sui_bank, &boards, &cap, s.ctx());
    arcade::payout_cycle(&mut eve_bank, &boards, &cap, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(boards);
    ts::return_shared(sui_bank);
    ts::return_shared(eve_bank);
    assert!(received<SUI>(&mut s, player(2)) == 40_000_000_000);
    assert!(received<SUI>(&mut s, player(1)) == 25_000_000_000);
    assert!(received<SUI>(&mut s, player(3)) == 15_000_000_000);
    assert!(received<EVE>(&mut s, player(2)) == 6_000_000_000);
    assert!(received<EVE>(&mut s, player(1)) == 3_750_000_000);
    assert!(received<EVE>(&mut s, player(3)) == 2_250_000_000);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EAlreadyPaid)]
fun cycle_payout_twice_from_one_bank_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 2);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    let mut bank = s.take_shared<Bank<SUI>>();
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    abort
}

#[test, expected_failure(abort_code = arcade::ETooEarly)]
fun cycle_scan_only_after_end_plus_review() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 2);
    clock.set_for_testing(at(W + 2, 24 * HOUR - 1));
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    abort
}

#[test, expected_failure(abort_code = arcade::EScanNotDone)]
fun cycle_payout_needs_finished_scan() {
    let mut s = ts::begin(ADMIN);
    let _clock = setup(&mut s, 2);
    s.next_tx(SERVER);
    let boards = s.take_shared<Boards>();
    let mut bank = s.take_shared<Bank<SUI>>();
    let cap = s.take_from_sender<OperatorCap>();
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    abort
}

#[test, expected_failure(abort_code = arcade::ECycleEndUnset)]
fun scan_cycle_while_end_unset_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 0);
    clock.set_for_testing(at(W + 52, 0));
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    abort
}

#[test, expected_failure(abort_code = arcade::ECycleEndUnset)]
fun payout_cycle_while_end_unset_aborts() {
    let mut s = ts::begin(ADMIN);
    let _clock = setup(&mut s, 0);
    s.next_tx(SERVER);
    let boards = s.take_shared<Boards>();
    let mut bank = s.take_shared<Bank<SUI>>();
    let cap = s.take_from_sender<OperatorCap>();
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    abort
}

#[test]
fun emergency_end_now_then_cycle_payout_after_review() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 0);
    pay_n<SUI>(&mut s, &clock, PRICE, 2);
    record(&mut s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W, 3 * DAY));
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_cycle_end_now(&admin, &clock);
    s.return_to_sender(admin);
    ts::return_shared(boards);
    clock.set_for_testing(at(W, 4 * DAY));
    finalize(&mut s, &clock, W);
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    assert!(boards.scan_done() && boards.scan_top() == vector[player(1)]);
    let mut bank = s.take_shared<Bank<SUI>>();
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(boards);
    ts::return_shared(bank);
    assert!(received<SUI>(&mut s, player(1)) == 120_000_000);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun paused_eve_bank_does_not_block_sui_payout() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    pay_n<SUI>(&mut s, &clock, PRICE, 4);
    pay_n<EVE>(&mut s, &clock, EVE_PRICE, 2);
    record(&mut s, &clock, W, player(1), 900);
    record(&mut s, &clock, W, player(2), 800);
    record(&mut s, &clock, W, player(3), 700);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    admin_pause(&mut s, false);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    assert!(received<SUI>(&mut s, player(2)) == 300_000_000);
    assert!(received<SUI>(&mut s, player(3)) == 200_000_000);
    assert!(received<EVE>(&mut s, player(1)) == 0);
    assert!(closed<SUI>(&mut s) == 0);
    s.next_tx(ADMIN);
    let sui_bank = s.take_shared<Bank<SUI>>();
    let eve_bank = s.take_shared<Bank<EVE>>();
    assert!(sui_bank.is_week_paid(W));
    assert!(!eve_bank.is_week_paid(W) && eve_bank.week_bank() == 5_000_000_000 && eve_bank.closed_bank() == 0);
    ts::return_shared(sui_bank);
    ts::return_shared(eve_bank);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ENotFinalized)]
fun scan_cycle_needs_every_week_finalized() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 2);
    record(&mut s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W + 1, 25 * HOUR));
    record(&mut s, &clock, W + 1, player(2), 800);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    finalize(&mut s, &clock, W + 1);
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    abort
}

fun other_boards_bank(s: &mut Scenario, clock: &Clock): (ID, ID) { other_boards_bank_ending(s, clock, 0) }

fun other_boards_bank_ending(s: &mut Scenario, clock: &Clock, end: u64): (ID, ID) {
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<SUI>>();
    let first = bank.boards_id();
    ts::return_shared(bank);
    s.next_tx(ADMIN);
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, end, 1_000_000, clock, s.ctx());
    transfer::public_transfer(op, ADMIN);
    transfer::public_transfer(signer, ADMIN);
    transfer::public_transfer(moderator, ADMIN);
    let effects = s.next_tx(ADMIN);
    assert!(effects.shared().length() == 1);
    let second = *effects.shared().borrow(0);
    let mut boards = s.take_shared_by_id<Boards>(second);
    let bank = arcade::create_bank<SUI>(&admin, &mut boards, OWNER, PRICE, clock, s.ctx());
    ts::return_shared(boards);
    s.return_to_sender(admin);
    (first, bank)
}

#[test, expected_failure(abort_code = arcade::EWrongBoards)]
fun payout_week_with_bank_of_other_boards_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    let (first, other_bank) = other_boards_bank(&mut s, &clock);
    s.next_tx(SERVER);
    let mut bank = s.take_shared_by_id<Bank<SUI>>(other_bank);
    let boards = s.take_shared_by_id<Boards>(first);
    let cap = s.take_from_sender<OperatorCap>();
    arcade::payout_week(&mut bank, &boards, &cap, W, &clock, s.ctx());
    abort
}

#[test, expected_failure(abort_code = arcade::EWrongBoards)]
fun payout_cycle_with_bank_of_other_boards_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 2);
    let (first, other_bank) = other_boards_bank(&mut s, &clock);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    s.next_tx(SERVER);
    let mut boards = s.take_shared_by_id<Boards>(first);
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    let mut bank = s.take_shared_by_id<Bank<SUI>>(other_bank);
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    abort
}

#[test, expected_failure(abort_code = arcade::ENotOperator)]
fun rotated_operator_cannot_pay_cycle() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 2);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    s.return_to_sender(cap);
    ts::return_shared(boards);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    let fresh = boards.rotate_operator(&admin, s.ctx());
    transfer::public_transfer(fresh, ADMIN);
    s.return_to_sender(admin);
    ts::return_shared(boards);
    s.next_tx(SERVER);
    let boards = s.take_shared<Boards>();
    let mut bank = s.take_shared<Bank<SUI>>();
    let cap = s.take_from_sender<OperatorCap>();
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    abort
}

#[test]
fun cycle_tie_on_points_and_best_goes_to_earlier_best() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 2);
    record(&mut s, &clock, W, player(2), 100);
    clock.set_for_testing(at(W, DAY + 1));
    record(&mut s, &clock, W, player(1), 500);
    clock.set_for_testing(at(W, DAY + 2));
    record(&mut s, &clock, W, player(2), 500);
    clock.set_for_testing(at(W + 1, 25 * HOUR));
    finalize(&mut s, &clock, W);
    record(&mut s, &clock, W + 1, player(2), 400);
    record(&mut s, &clock, W + 1, player(1), 300);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    finalize(&mut s, &clock, W + 1);
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    assert!(boards.points_of(player(1)) == 17 && boards.points_of(player(2)) == 17);
    assert!(boards.best_of(player(1)) == 500 && boards.best_of(player(2)) == 500);
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    assert!(boards.scan_top() == vector[player(1), player(2)]);
    s.return_to_sender(cap);
    ts::return_shared(boards);
    clock.destroy_for_testing();
    s.end();
}

fun twelve_players(s: &mut Scenario, clock: &mut Clock) {
    let mut n = 1;
    while (n <= 12) {
        record(s, clock, W, player(n), 1000 - n);
        n = n + 1;
    };
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(s, clock, W);
}

fun top10(): vector<address> {
    let mut v = vector[];
    let mut n = 1;
    while (n <= 10) {
        v.push_back(player(n));
        n = n + 1;
    };
    v
}

#[test]
fun scan_top_keeps_ten_of_twelve_ranked() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 1);
    twelve_players(&mut s, &mut clock);
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 100, &clock);
    assert!(boards.scan_done());
    assert!(boards.points_of(player(11)) == 1 && boards.points_of(player(12)) == 1);
    assert!(boards.scan_top() == top10());
    s.return_to_sender(cap);
    ts::return_shared(boards);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun scan_pages_of_five_over_twelve_players() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 1);
    twelve_players(&mut s, &mut clock);
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 5, &clock);
    assert!(!boards.scan_done());
    boards.scan_cycle(&cap, 5, &clock);
    assert!(!boards.scan_done());
    boards.scan_cycle(&cap, 5, &clock);
    assert!(boards.scan_done());
    assert!(boards.scan_top() == top10());
    s.return_to_sender(cap);
    ts::return_shared(boards);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun is_week_paid_false_for_unpaid_week() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 8);
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<SUI>>();
    assert!(!bank.is_week_paid(W) && !bank.cycle_paid());
    ts::return_shared(bank);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<SUI>>();
    assert!(bank.is_week_paid(W) && !bank.is_week_paid(W + 1) && !bank.is_week_paid(W - 1));
    ts::return_shared(bank);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun first_week_moves_only_on_recorded_results() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s, 8);
    s.next_tx(ADMIN);
    let boards = s.take_shared<Boards>();
    assert!(boards.first_week_for_testing() == 18_446_744_073_709_551_615);
    ts::return_shared(boards);
    record(&mut s, &clock, W, player(1), 900);
    finalize(&mut s, &clock, W - 1);
    s.next_tx(ADMIN);
    let boards = s.take_shared<Boards>();
    assert!(boards.is_finalized(W - 1));
    assert!(boards.first_week_for_testing() == W);
    ts::return_shared(boards);
    clock.destroy_for_testing();
    s.end();
}

fun sui_bank_id(s: &mut Scenario): ID {
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<SUI>>();
    let id = object::id(&bank);
    ts::return_shared(bank);
    id
}

fun finished_cycle(s: &mut Scenario, pay_week: bool, pay_cycle: bool): Clock {
    let mut clock = setup(s, 1);
    s.next_tx(OWNER);
    let mut bank = s.take_shared<Bank<SUI>>();
    arcade::fund_cycle(&mut bank, coin::mint_for_testing<SUI>(100_000_000_000, s.ctx()), s.ctx());
    ts::return_shared(bank);
    pay_n<SUI>(s, &clock, PRICE, 4);
    record(s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(s, &clock, W);
    if (pay_week) payout<SUI>(s, &clock, W);
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, &clock);
    if (pay_cycle) {
        let mut bank = s.take_shared<Bank<SUI>>();
        arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
        ts::return_shared(bank);
    };
    s.return_to_sender(cap);
    ts::return_shared(boards);
    clock
}

fun carry(s: &mut Scenario, old_bank: ID, old_boards: ID, new_bank: ID) {
    s.next_tx(ADMIN);
    let mut from = s.take_shared_by_id<Bank<SUI>>(old_bank);
    let boards = s.take_shared_by_id<Boards>(old_boards);
    let mut to = s.take_shared_by_id<Bank<SUI>>(new_bank);
    let admin = s.take_from_sender<AdminCap>();
    arcade::carry_over(&mut from, &boards, &mut to, &admin);
    s.return_to_sender(admin);
    ts::return_shared(from);
    ts::return_shared(boards);
    ts::return_shared(to);
}

#[test]
fun carry_over_moves_all_leftovers_into_next_cycle_bank() {
    let mut s = ts::begin(ADMIN);
    let clock = finished_cycle(&mut s, true, true);
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<SUI>>();
    assert!(bank.week_bank() == 0 && bank.closed_bank() == 500_000_000 && bank.cycle_bank() == 60_360_000_000);
    ts::return_shared(bank);
    let old_bank = sui_bank_id(&mut s);
    let (old_boards, new_bank) = other_boards_bank(&mut s, &clock);
    carry(&mut s, old_bank, old_boards, new_bank);
    s.next_tx(ADMIN);
    let from = s.take_shared_by_id<Bank<SUI>>(old_bank);
    let to = s.take_shared_by_id<Bank<SUI>>(new_bank);
    assert!(from.week_bank() == 0 && from.closed_bank() == 0 && from.cycle_bank() == 0);
    assert!(to.cycle_bank() == 60_860_000_000 && to.week_bank() == 0 && to.closed_bank() == 0);
    ts::return_shared(from);
    ts::return_shared(to);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ENotPaidOut)]
fun carry_over_before_cycle_paid_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = finished_cycle(&mut s, true, false);
    let old_bank = sui_bank_id(&mut s);
    let (old_boards, new_bank) = other_boards_bank(&mut s, &clock);
    carry(&mut s, old_bank, old_boards, new_bank);
    abort
}

#[test, expected_failure(abort_code = arcade::ENotPaidOut)]
fun carry_over_while_last_week_unpaid_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = finished_cycle(&mut s, false, true);
    let old_bank = sui_bank_id(&mut s);
    let (old_boards, new_bank) = other_boards_bank(&mut s, &clock);
    carry(&mut s, old_bank, old_boards, new_bank);
    abort
}

fun scan_and_pay_cycle(s: &mut Scenario, clock: &Clock) {
    s.next_tx(SERVER);
    let mut boards = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    boards.scan_cycle(&cap, 10, clock);
    let mut bank = s.take_shared<Bank<SUI>>();
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    ts::return_shared(bank);
    s.return_to_sender(cap);
    ts::return_shared(boards);
}

fun two_week_cycle(s: &mut Scenario): Clock {
    let mut clock = setup(s, 2);
    pay_n<SUI>(s, &clock, PRICE, 4);
    record(s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W + 1, 25 * HOUR));
    clock
}

#[test, expected_failure(abort_code = arcade::ENotPaidOut)]
fun payout_later_week_before_earlier_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = two_week_cycle(&mut s);
    finalize(&mut s, &clock, W);
    record(&mut s, &clock, W + 1, player(2), 800);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    finalize(&mut s, &clock, W + 1);
    payout<SUI>(&mut s, &clock, W + 1);
    abort
}

#[test]
fun weeks_paid_in_order_each_get_exact_share() {
    let mut s = ts::begin(ADMIN);
    let mut clock = two_week_cycle(&mut s);
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    pay_n<SUI>(&mut s, &clock, PRICE, 2);
    record(&mut s, &clock, W + 1, player(2), 800);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    finalize(&mut s, &clock, W + 1);
    payout<SUI>(&mut s, &clock, W + 1);
    assert!(received<SUI>(&mut s, player(2)) == 500_000_000);
    scan_and_pay_cycle(&mut s, &clock);
    let old_bank = sui_bank_id(&mut s);
    let (old_boards, new_bank) = other_boards_bank(&mut s, &clock);
    carry(&mut s, old_bank, old_boards, new_bank);
    s.next_tx(ADMIN);
    let to = s.take_shared_by_id<Bank<SUI>>(new_bank);
    assert!(to.cycle_bank() == 815_000_000);
    ts::return_shared(to);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ENotPaidOut)]
fun payout_while_earlier_board_unfinalized_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = two_week_cycle(&mut s);
    record(&mut s, &clock, W + 1, player(2), 800);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    finalize(&mut s, &clock, W + 1);
    payout<SUI>(&mut s, &clock, W + 1);
    abort
}

#[test]
fun late_finalized_earlier_week_paid_first_then_later_week() {
    let mut s = ts::begin(ADMIN);
    let mut clock = two_week_cycle(&mut s);
    record(&mut s, &clock, W + 1, player(2), 800);
    clock.set_for_testing(at(W + 2, 24 * HOUR));
    finalize(&mut s, &clock, W + 1);
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    payout<SUI>(&mut s, &clock, W + 1);
    assert!(received<SUI>(&mut s, player(2)) == 250_000_000);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ENotPaidOut)]
fun carry_over_with_earlier_week_unpaid_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 3);
    record(&mut s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    clock.set_for_testing(at(W + 2, DAY));
    record(&mut s, &clock, W + 2, player(2), 800);
    clock.set_for_testing(at(W + 3, 24 * HOUR));
    finalize(&mut s, &clock, W + 2);
    payout<SUI>(&mut s, &clock, W + 2);
    scan_and_pay_cycle(&mut s, &clock);
    finalize(&mut s, &clock, W + 1);
    let old_bank = sui_bank_id(&mut s);
    let (old_boards, new_bank) = other_boards_bank(&mut s, &clock);
    carry(&mut s, old_bank, old_boards, new_bank);
    abort
}

#[test]
fun partial_last_week_pays_its_own_fees_then_carry_moves_dust() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 0);
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_cycle_end_ms(&admin, at(W, 3 * DAY), &clock);
    s.return_to_sender(admin);
    ts::return_shared(boards);
    pay_n<SUI>(&mut s, &clock, PRICE, 4);
    record(&mut s, &clock, W, player(1), 900);
    record(&mut s, &clock, W, player(2), 800);
    record(&mut s, &clock, W, player(3), 700);
    clock.set_for_testing(at(W, 4 * DAY));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    assert!(received<SUI>(&mut s, player(2)) == 300_000_000);
    assert!(received<SUI>(&mut s, player(3)) == 200_000_000);
    assert!(closed<SUI>(&mut s) == 0);
    scan_and_pay_cycle(&mut s, &clock);
    let old_bank = sui_bank_id(&mut s);
    let (old_boards, new_bank) = other_boards_bank(&mut s, &clock);
    carry(&mut s, old_bank, old_boards, new_bank);
    s.next_tx(ADMIN);
    let to = s.take_shared_by_id<Bank<SUI>>(new_bank);
    assert!(to.cycle_bank() == 120_000_000);
    ts::return_shared(to);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ECycleEnded)]
fun carry_over_into_already_paid_cycle_bank_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = finished_cycle(&mut s, true, true);
    let old_bank = sui_bank_id(&mut s);
    let now = clock.timestamp_ms();
    let (old_boards, new_bank) = other_boards_bank_ending(&mut s, &clock, now + 1);
    clock.set_for_testing(now + 1 + 24 * HOUR);
    s.next_tx(ADMIN);
    let mut bank = s.take_shared_by_id<Bank<SUI>>(new_bank);
    let mut boards = s.take_shared_by_id<Boards>(bank.boards_id());
    let admin = s.take_from_sender<AdminCap>();
    let cap = boards.rotate_operator(&admin, s.ctx());
    boards.scan_cycle(&cap, 10, &clock);
    arcade::payout_cycle(&mut bank, &boards, &cap, s.ctx());
    assert!(bank.cycle_paid());
    transfer::public_transfer(cap, ADMIN);
    s.return_to_sender(admin);
    ts::return_shared(boards);
    ts::return_shared(bank);
    carry(&mut s, old_bank, old_boards, new_bank);
    abort
}

#[test, expected_failure(abort_code = arcade::EZeroAmount)]
fun carry_over_of_empty_bank_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s, 1);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    payout<SUI>(&mut s, &clock, W);
    scan_and_pay_cycle(&mut s, &clock);
    let old_bank = sui_bank_id(&mut s);
    let (old_boards, new_bank) = other_boards_bank(&mut s, &clock);
    carry(&mut s, old_bank, old_boards, new_bank);
    abort
}

fun bank_week_value<T>(s: &mut Scenario): u64 {
    s.next_tx(ADMIN);
    let bank = s.take_shared<Bank<T>>();
    let v = bank.week_bank();
    ts::return_shared(bank);
    v
}

fun set_end(s: &mut Scenario, clock: &Clock, ms: u64) {
    s.next_tx(ADMIN);
    let mut boards = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    boards.set_cycle_end_ms(&admin, ms, clock);
    s.return_to_sender(admin);
    ts::return_shared(boards);
}

fun end_inside_review_of_previous_week(s: &mut Scenario): Clock {
    let mut clock = setup(s, 0);
    set_end(s, &clock, at(W + 1, 12 * HOUR));
    pay_n<SUI>(s, &clock, PRICE, 4);
    record(s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W + 1, HOUR));
    pay_n<SUI>(s, &clock, PRICE, 4);
    record(s, &clock, W + 1, player(2), 800);
    clock.set_for_testing(at(W + 1, 25 * HOUR));
    finalize(s, &clock, W);
    clock
}

#[test]
fun week_before_last_paid_after_cycle_end_takes_only_its_own_fees() {
    let mut s = ts::begin(ADMIN);
    let mut clock = end_inside_review_of_previous_week(&mut s);
    payout<SUI>(&mut s, &clock, W);
    assert!(received<SUI>(&mut s, player(1)) == 500_000_000);
    assert!(closed<SUI>(&mut s) == 500_000_000);
    assert!(bank_week_value<SUI>(&mut s) == 1_000_000_000);
    clock.set_for_testing(at(W + 1, 36 * HOUR));
    finalize(&mut s, &clock, W + 1);
    payout<SUI>(&mut s, &clock, W + 1);
    assert!(received<SUI>(&mut s, player(2)) == 750_000_000);
    assert!(closed<SUI>(&mut s) == 750_000_000);
    assert!(bank_week_value<SUI>(&mut s) == 0);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun cycle_end_pushed_out_keeps_last_week_fees_unpooled() {
    let mut s = ts::begin(ADMIN);
    let clock = end_inside_review_of_previous_week(&mut s);
    payout<SUI>(&mut s, &clock, W);
    set_end(&mut s, &clock, at(W + 3, 0));
    assert!(bank_week_value<SUI>(&mut s) == 1_000_000_000);
    assert!(closed<SUI>(&mut s) == 500_000_000);
    clock.destroy_for_testing();
    s.end();
}
