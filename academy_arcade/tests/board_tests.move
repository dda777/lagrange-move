#[test_only]
module academy_arcade::board_tests;

use academy_arcade::arcade::{Self, AdminCap, Boards, ModeratorCap, OperatorCap, ResultSignerCap};
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};

const ADMIN: address = @0xAD;
const SERVER: address = @0x5E;
const MOD: address = @0x30;
const DAY: u64 = 86_400_000;
const HOUR: u64 = 3_600_000;
const WEEK: u64 = 604_800_000;
const ANCHOR: u64 = 345_600_000;
const MAX_SCORE: u64 = 1_000_000;
const W: u64 = 2900;
const HASH: vector<u8> = x"abababababababababababababababababababababababababababababababab";

fun at(week: u64, offset: u64): u64 { ANCHOR + week * WEEK + offset }

fun player(n: u64): address { sui::address::from_u256((0xB000 + n) as u256) }

fun setup(s: &mut Scenario): Clock {
    arcade::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(at(W, DAY));
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, at(W + 8, 0), MAX_SCORE, &clock, s.ctx());
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(moderator, MOD);
    s.return_to_sender(admin);
    clock
}

fun record(s: &mut Scenario, clock: &Clock, week: u64, who: address, score: u64) {
    s.next_tx(SERVER);
    let mut b = s.take_shared<Boards>();
    let cap = s.take_from_sender<ResultSignerCap>();
    b.record_result(&cap, week, who, object::id_from_address(who), score, HASH, clock, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(b);
}

fun finalize(s: &mut Scenario, clock: &Clock, week: u64) {
    s.next_tx(SERVER);
    let mut b = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    b.finalize_week(&cap, week, clock, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(b);
}

fun top(s: &mut Scenario, week: u64): vector<address> {
    s.next_tx(ADMIN);
    let b = s.take_shared<Boards>();
    let r = b.top_players(week);
    ts::return_shared(b);
    r
}

fun scores(s: &mut Scenario, week: u64): vector<u64> {
    s.next_tx(ADMIN);
    let b = s.take_shared<Boards>();
    let r = b.top_scores(week);
    ts::return_shared(b);
    r
}

fun points(s: &mut Scenario, who: address): u64 {
    s.next_tx(ADMIN);
    let b = s.take_shared<Boards>();
    let p = b.points_of(who);
    ts::return_shared(b);
    p
}

fun remove(s: &mut Scenario, clock: &Clock, week: u64, who: address) {
    s.next_tx(MOD);
    let mut b = s.take_shared<Boards>();
    let cap = s.take_from_sender<ModeratorCap>();
    b.remove_result(&cap, week, who, clock, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(b);
}

fun set_league(s: &mut Scenario, places: vector<u64>, participation: u64) {
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    b.set_league_points(&admin, places, participation);
    s.return_to_sender(admin);
    ts::return_shared(b);
}

fun setup_short_cycle(s: &mut Scenario): Clock {
    arcade::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(at(W, DAY));
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, at(W + 1, 3 * DAY), MAX_SCORE, &clock, s.ctx());
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(moderator, MOD);
    s.return_to_sender(admin);
    clock
}

#[test]
fun first_result_counts_participation() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 100);
    assert!(points(&mut s, player(1)) == 1);
    assert!(top(&mut s, W) == vector[player(1)]);
    assert!(scores(&mut s, W) == vector[100]);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun top10_keeps_best_and_drops_eleventh() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    let mut i = 1;
    while (i <= 11) {
        record(&mut s, &clock, W, player(i), i * 10);
        i = i + 1;
    };
    let t = top(&mut s, W);
    assert!(t.length() == 10);
    assert!(*t.borrow(0) == player(11) && *scores(&mut s, W).borrow(0) == 110);
    assert!(!t.contains(&player(1)));
    record(&mut s, &clock, W, player(2), 500);
    let t2 = top(&mut s, W);
    assert!(*t2.borrow(0) == player(2) && t2.length() == 10);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun tie_earlier_stays_above() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 300);
    clock.increment_for_testing(1000);
    record(&mut s, &clock, W, player(2), 300);
    assert!(top(&mut s, W) == vector[player(1), player(2)]);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ENothingChanged)]
fun result_that_changes_nothing_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 300);
    record(&mut s, &clock, W, player(1), 200);
    abort
}

#[test, expected_failure(abort_code = arcade::EScoreTooHigh)]
fun score_above_ceiling_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), MAX_SCORE + 1);
    abort
}

#[test]
fun previous_week_accepted_inside_review_window() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, 23 * HOUR));
    record(&mut s, &clock, W, player(1), 100);
    assert!(top(&mut s, W) == vector[player(1)]);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EWeekClosed)]
fun previous_week_rejected_after_review_window() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    record(&mut s, &clock, W, player(1), 100);
    abort
}

#[test, expected_failure(abort_code = arcade::ENotSigner)]
fun rotated_signer_cannot_record() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    let fresh = b.rotate_signer(&admin, s.ctx());
    transfer::public_transfer(fresh, ADMIN);
    s.return_to_sender(admin);
    ts::return_shared(b);
    record(&mut s, &clock, W, player(1), 100);
    abort
}

#[test, expected_failure(abort_code = arcade::ENotSigner)]
fun signer_cap_of_other_boards_rejected() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    s.next_tx(ADMIN);
    let old_id = ts::most_recent_id_shared<Boards>().destroy_some();
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, at(W + 16, 0), MAX_SCORE, &clock, s.ctx());
    transfer::public_transfer(op, ADMIN);
    transfer::public_transfer(signer, ADMIN);
    transfer::public_transfer(moderator, ADMIN);
    s.return_to_sender(admin);
    s.next_tx(SERVER);
    let new_id = ts::most_recent_id_shared<Boards>().destroy_some();
    assert!(new_id != old_id);
    let mut b = s.take_shared_by_id<Boards>(new_id);
    let cap = s.take_from_sender<ResultSignerCap>();
    b.record_result(&cap, W, player(1), object::id_from_address(player(1)), 100, HASH, &clock, s.ctx());
    abort
}

#[test]
fun moderator_removes_within_window_and_disqualifies() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 900);
    record(&mut s, &clock, W, player(2), 100);
    clock.set_for_testing(at(W + 1, HOUR));
    remove(&mut s, &clock, W, player(1));
    assert!(top(&mut s, W) == vector[player(2)]);
    assert!(points(&mut s, player(1)) == 0);
    assert!(points(&mut s, player(2)) == 1);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EDisqualified)]
fun disqualified_player_cannot_be_recorded_again() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 900);
    remove(&mut s, &clock, W, player(1));
    record(&mut s, &clock, W, player(1), 950);
    abort
}

#[test, expected_failure(abort_code = arcade::EReviewClosed)]
fun removal_after_review_window_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    remove(&mut s, &clock, W, player(1));
    abort
}

#[test, expected_failure(abort_code = arcade::ENotModerator)]
fun revoked_moderator_cannot_remove() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 900);
    s.next_tx(MOD);
    let cap = s.take_from_sender<ModeratorCap>();
    let cap_id = object::id(&cap);
    s.return_to_sender(cap);
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    b.revoke_moderator(&admin, cap_id);
    s.return_to_sender(admin);
    ts::return_shared(b);
    remove(&mut s, &clock, W, player(1));
    abort
}

#[test]
fun finalize_awards_league_points_10_7_5_3() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    let mut i = 1;
    while (i <= 5) {
        record(&mut s, &clock, W, player(i), 1000 - i);
        i = i + 1;
    };
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    assert!(points(&mut s, player(1)) == 10);
    assert!(points(&mut s, player(2)) == 7);
    assert!(points(&mut s, player(3)) == 5);
    assert!(points(&mut s, player(4)) == 3);
    assert!(points(&mut s, player(5)) == 3);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::ETooEarly)]
fun finalize_before_review_end_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 1);
    clock.set_for_testing(at(W + 1, 24 * HOUR - 1));
    finalize(&mut s, &clock, W);
    abort
}

#[test, expected_failure(abort_code = arcade::EAlreadyFinalized)]
fun finalize_twice_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    finalize(&mut s, &clock, W);
    abort
}

#[test]
fun last_partial_week_closes_at_cycle_end() {
    let mut s = ts::begin(ADMIN);
    arcade::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(at(W, DAY));
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, at(W + 1, 3 * DAY), MAX_SCORE, &clock, s.ctx());
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(moderator, MOD);
    s.return_to_sender(admin);
    clock.set_for_testing(at(W + 1, 3 * DAY + HOUR));
    record(&mut s, &clock, W + 1, player(1), 100);
    clock.set_for_testing(at(W + 1, 4 * DAY));
    finalize(&mut s, &clock, W + 1);
    assert!(points(&mut s, player(1)) == 10);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun weeks_close_by_calendar_while_cycle_end_unset() {
    let mut s = ts::begin(ADMIN);
    arcade::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(at(W, DAY));
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, 0, MAX_SCORE, &clock, s.ctx());
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(moderator, MOD);
    s.return_to_sender(admin);
    record(&mut s, &clock, W, player(1), 100);
    clock.set_for_testing(at(W + 1, DAY));
    finalize(&mut s, &clock, W);
    assert!(points(&mut s, player(1)) == 10);
    clock.set_for_testing(at(W + 30, HOUR));
    record(&mut s, &clock, W + 30, player(2), 50);
    assert!(top(&mut s, W + 30) == vector[player(2)]);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EWeekClosed)]
fun record_for_future_week_rejected() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    record(&mut s, &clock, W + 1, player(1), 100);
    abort
}

#[test, expected_failure(abort_code = arcade::ETooEarly)]
fun finalize_future_week_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    finalize(&mut s, &clock, W + 1);
    abort
}

#[test, expected_failure(abort_code = arcade::ETooEarly)]
fun finalize_week_after_cycle_end_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup_short_cycle(&mut s);
    clock.set_for_testing(at(W + 2, DAY));
    finalize(&mut s, &clock, W + 2);
    abort
}

#[test, expected_failure(abort_code = arcade::EBadCycleEnd)]
fun cycle_end_frozen_after_last_week_finalized() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup_short_cycle(&mut s);
    clock.set_for_testing(at(W + 1, 4 * DAY));
    finalize(&mut s, &clock, W + 1);
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    b.set_cycle_end_ms(&admin, at(W + 3, 0), &clock);
    abort
}

#[test]
fun cycle_end_movable_before_last_week_finalized() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup_short_cycle(&mut s);
    clock.set_for_testing(at(W + 1, 4 * DAY));
    finalize(&mut s, &clock, W);
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    b.set_cycle_end_ms(&admin, at(W + 3, 0), &clock);
    assert!(b.cycle_end_ms() == at(W + 3, 0));
    s.return_to_sender(admin);
    ts::return_shared(b);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun participation_change_mid_week_uses_week_snapshot() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 900);
    set_league(&mut s, vector[10, 7, 5], 2);
    record(&mut s, &clock, W, player(2), 800);
    clock.set_for_testing(at(W + 1, 24 * HOUR));
    finalize(&mut s, &clock, W);
    assert!(points(&mut s, player(1)) == 10);
    assert!(points(&mut s, player(2)) == 7);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun removal_subtracts_week_snapshot() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 900);
    set_league(&mut s, vector[10, 7, 5], 0);
    remove(&mut s, &clock, W, player(1));
    assert!(points(&mut s, player(1)) == 0);
    clock.destroy_for_testing();
    s.end();
}

#[test]
fun double_removal_subtracts_participation_once() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    record(&mut s, &clock, W, player(1), 900);
    clock.set_for_testing(at(W + 1, HOUR));
    record(&mut s, &clock, W + 1, player(1), 900);
    assert!(points(&mut s, player(1)) == 2);
    remove(&mut s, &clock, W, player(1));
    remove(&mut s, &clock, W, player(1));
    assert!(points(&mut s, player(1)) == 1);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EWeekClosed)]
fun removal_for_future_week_aborts() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    remove(&mut s, &clock, W + 1, player(1));
    abort
}

#[test, expected_failure(abort_code = arcade::EWeekClosed)]
fun removal_for_week_starting_at_cycle_end_aborts() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    b.set_cycle_end_ms(&admin, at(W + 1, 0), &clock);
    s.return_to_sender(admin);
    ts::return_shared(b);
    clock.set_for_testing(at(W + 1, HOUR));
    remove(&mut s, &clock, W + 1, player(1));
    abort
}
