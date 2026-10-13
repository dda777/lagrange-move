#[test_only]
module academy_arcade::marathon_tests;

use academy_arcade::arcade::{Self, AdminCap, Boards, MarathonBadge, OperatorCap};
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};

const ADMIN: address = @0xAD;
const SERVER: address = @0x5E;
const MOD: address = @0x30;
const RUNNER: address = @0xB1;
const DAY: u64 = 86_400_000;
const WEEK: u64 = 604_800_000;
const ANCHOR: u64 = 345_600_000;
const W: u64 = 2900;

fun at(week: u64, offset: u64): u64 { ANCHOR + week * WEEK + offset }

fun setup(s: &mut Scenario): Clock {
    arcade::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(at(W, DAY));
    let admin = s.take_from_sender<AdminCap>();
    let (op, signer, moderator) = arcade::create_boards(&admin, ANCHOR, at(W + 8, 0), 1_000_000, &clock, s.ctx());
    transfer::public_transfer(op, SERVER);
    transfer::public_transfer(signer, SERVER);
    transfer::public_transfer(moderator, MOD);
    s.return_to_sender(admin);
    clock
}

fun mint(s: &mut Scenario, clock: &Clock, week: u64, player: address, place: u64) {
    s.next_tx(SERVER);
    let mut b = s.take_shared<Boards>();
    let cap = s.take_from_sender<OperatorCap>();
    b.mint_marathon_badge(&cap, week, player, place, 4321, clock, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(b);
}

#[test]
fun mints_soulbound_badge_after_week_once() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, DAY));
    mint(&mut s, &clock, W, RUNNER, 1);
    s.next_tx(RUNNER);
    let badge = s.take_from_sender<MarathonBadge>();
    assert!(badge.marathon_week() == W);
    assert!(badge.marathon_place() == 1);
    s.return_to_sender(badge);
    s.next_tx(ADMIN);
    let b = s.take_shared<Boards>();
    assert!(b.marathon_minted(W, RUNNER));
    assert!(!b.marathon_minted(W + 1, RUNNER));
    ts::return_shared(b);
    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = arcade::EMarathonMinted)]
fun second_mint_same_week_fails() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, DAY));
    mint(&mut s, &clock, W, RUNNER, 1);
    mint(&mut s, &clock, W, RUNNER, 2);
    abort
}

#[test, expected_failure(abort_code = arcade::EWeekNotOver)]
fun current_week_cannot_be_minted() {
    let mut s = ts::begin(ADMIN);
    let clock = setup(&mut s);
    mint(&mut s, &clock, W, RUNNER, 1);
    abort
}

#[test, expected_failure(abort_code = arcade::EBadPlace)]
fun place_zero_fails() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, DAY));
    mint(&mut s, &clock, W, RUNNER, 0);
    abort
}

#[test, expected_failure(abort_code = arcade::EPaused)]
fun paused_boards_refuse() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, DAY));
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    b.set_paused(&admin, true);
    s.return_to_sender(admin);
    ts::return_shared(b);
    mint(&mut s, &clock, W, RUNNER, 1);
    abort
}

#[test, expected_failure(abort_code = arcade::EBadPlace)]
fun place_above_twenty_fails() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, DAY));
    mint(&mut s, &clock, W, RUNNER, 21);
    abort
}

#[test, expected_failure(abort_code = arcade::ENotOperator)]
fun stale_operator_cap_refused() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 1, DAY));
    s.next_tx(ADMIN);
    let mut b = s.take_shared<Boards>();
    let admin = s.take_from_sender<AdminCap>();
    let fresh = b.rotate_operator(&admin, s.ctx());
    transfer::public_transfer(fresh, ADMIN);
    s.return_to_sender(admin);
    ts::return_shared(b);
    mint(&mut s, &clock, W, RUNNER, 1);
    abort
}

#[test]
fun other_week_and_other_player_mint_separately() {
    let mut s = ts::begin(ADMIN);
    let mut clock = setup(&mut s);
    clock.set_for_testing(at(W + 2, DAY));
    mint(&mut s, &clock, W, RUNNER, 1);
    mint(&mut s, &clock, W + 1, RUNNER, 3);
    mint(&mut s, &clock, W, @0xB2, 20);
    s.next_tx(ADMIN);
    let b = s.take_shared<Boards>();
    assert!(b.marathon_minted(W, RUNNER) && b.marathon_minted(W + 1, RUNNER) && b.marathon_minted(W, @0xB2));
    assert!(!b.marathon_minted(W + 1, @0xB2));
    ts::return_shared(b);
    clock.destroy_for_testing();
    s.end();
}
