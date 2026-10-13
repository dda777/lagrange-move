module academy_arcade::arcade;

use std::ascii::String;
use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::dynamic_field;
use sui::event;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

const VERSION: u64 = 1;
const BPS: u64 = 10_000;
const WEEK_MS: u64 = 604_800_000;
const HOUR_MS: u64 = 3_600_000;
const NONCE_LEN: u64 = 16;
const HASH_LEN: u64 = 32;
const BOARD_SIZE: u64 = 10;
const MAX_SHARES: u64 = 10;
const U64_MAX: u64 = 18_446_744_073_709_551_615;

#[error(code = 150)]
const EWrongVersion: vector<u8> = b"Object version does not match the package version";
#[error(code = 151)]
const EPaused: vector<u8> = b"Arcade or this currency bank is paused";
#[error(code = 152)]
const EWrongPrice: vector<u8> = b"Payment must equal the attempt price of this bank exactly";
#[error(code = 153)]
const ENonceLength: vector<u8> = b"Run nonce must be 16 bytes";
#[error(code = 154)]
const ECycleEnded: vector<u8> = b"The cycle has ended";
#[error(code = 155)]
const EBadSplit: vector<u8> = b"Split must have three parts summing to 10000 bps";
#[error(code = 156)]
const EBadShares: vector<u8> = b"Payout shares must have 1..10 parts summing to 10000 bps";
#[error(code = 157)]
const ENotOperator: vector<u8> = b"OperatorCap is not the current one of these boards";
#[error(code = 158)]
const ENotSigner: vector<u8> = b"ResultSignerCap is not the current one of these boards";
#[error(code = 159)]
const ENotModerator: vector<u8> = b"ModeratorCap is not active for these boards";
#[error(code = 160)]
const EWeekClosed: vector<u8> = b"Results for this week are not accepted now";
#[error(code = 161)]
const EScoreTooHigh: vector<u8> = b"Score is above the score ceiling";
#[error(code = 162)]
const EHashLength: vector<u8> = b"Replay hash must be 32 bytes";
#[error(code = 163)]
const ENothingChanged: vector<u8> = b"The result does not change the board";
#[error(code = 164)]
const EDisqualified: vector<u8> = b"The player is disqualified for this week";
#[error(code = 165)]
const EReviewClosed: vector<u8> = b"The review window of this week is closed";
#[error(code = 166)]
const ETooEarly: vector<u8> = b"Too early: the review window is not over";
#[error(code = 167)]
const EAlreadyFinalized: vector<u8> = b"The week is already finalized";
#[error(code = 168)]
const ENotFinalized: vector<u8> = b"The week is not finalized";
#[error(code = 169)]
const EAlreadyPaid: vector<u8> = b"This bank already paid this week or cycle";
#[error(code = 170)]
const EScanNotDone: vector<u8> = b"The cycle ranking scan is not finished";
#[error(code = 171)]
const EZeroAmount: vector<u8> = b"Amount must be greater than zero";
#[error(code = 172)]
const EBadLeague: vector<u8> = b"League points: 1..10 places";
#[error(code = 173)]
const EBadDelay: vector<u8> = b"Review delay must be 1..168 hours";
#[error(code = 174)]
const EBadCycleEnd: vector<u8> = b"Cycle end must be in the future and the cycle ranking not started";
#[error(code = 175)]
const EBadAnchor: vector<u8> = b"Week anchor must not be in the future";
#[error(code = 176)]
const ENotFound: vector<u8> = b"Unknown moderator cap or currency bank";
#[error(code = 177)]
const EWrongBoards: vector<u8> = b"The bank belongs to other boards";
#[error(code = 178)]
const EBankExists: vector<u8> = b"These boards already have a bank of this currency";
#[error(code = 179)]
const EMarathonMinted: vector<u8> = b"Marathon badge for this week and player is already minted";
#[error(code = 180)]
const EBadPlace: vector<u8> = b"Marathon place must be 1..20";
#[error(code = 181)]
const EWeekNotOver: vector<u8> = b"The marathon week is not over yet";
#[error(code = 182)]
const ECycleEndUnset: vector<u8> = b"The cycle end is not set yet";
#[error(code = 183)]
const ENotPaidOut: vector<u8> = b"This bank has not paid an earlier finalized week or the cycle yet";

public struct AdminCap has key, store { id: UID }

public struct OperatorCap has key, store { id: UID, boards_id: ID }

public struct ResultSignerCap has key, store { id: UID, boards_id: ID }

public struct ModeratorCap has key, store { id: UID, boards_id: ID }

public struct Entry has copy, drop, store {
    player: address,
    character_id: ID,
    score: u64,
    at_ms: u64,
    replay_hash: vector<u8>,
}

public struct WeekBoard has store {
    top: vector<Entry>,
    participants: Table<address, u64>,
    disqualified: Table<address, bool>,
    finalized: bool,
    participation: u64,
}

public struct PlayerCycle has copy, drop, store {
    points: u64,
    best: u64,
    best_at_ms: u64,
}

public struct Boards has key {
    id: UID,
    version: u64,
    paused: bool,
    place_points: vector<u64>,
    participation_points: u64,
    review_delay_ms: u64,
    week_anchor_ms: u64,
    cycle_end_ms: u64,
    max_score: u64,
    operator_cap_id: ID,
    signer_cap_id: ID,
    moderator_cap_ids: vector<ID>,
    banks: VecMap<TypeName, ID>,
    weeks: Table<u64, WeekBoard>,
    first_week: u64,
    players: Table<address, PlayerCycle>,
    player_list: vector<address>,
    scan_pos: u64,
    scan_top: vector<address>,
    scan_done: bool,
}

public struct Bank<phantom T> has key {
    id: UID,
    version: u64,
    boards_id: ID,
    paused: bool,
    owner: address,
    price: u64,
    split_bps: vector<u64>,
    week_shares_bps: vector<u64>,
    cycle_shares_bps: vector<u64>,
    week_bank: Balance<T>,
    bank_week: u64,
    closed_bank: Balance<T>,
    cycle_bank: Balance<T>,
    paid_weeks: Table<u64, bool>,
    cycle_paid: bool,
}

public struct BoardsCreated has copy, drop { boards_id: ID, week_anchor_ms: u64, cycle_end_ms: u64, max_score: u64 }

public struct BankCreated has copy, drop { boards_id: ID, bank_id: ID, coin_type: String, owner: address, price: u64 }

public struct AttemptPaid has copy, drop {
    boards_id: ID,
    bank_id: ID,
    coin_type: String,
    payer: address,
    run_nonce: vector<u8>,
    amount: u64,
    week: u64,
    to_week: u64,
    to_cycle: u64,
    to_owner: u64,
}

public struct CycleFunded has copy, drop { bank_id: ID, coin_type: String, funder: address, amount: u64, cycle_bank: u64 }

public struct ConfigChanged has copy, drop { object_id: ID, field: vector<u8> }

public struct CapRotated has copy, drop { boards_id: ID, kind: vector<u8>, cap_id: ID }

fun init(ctx: &mut TxContext) {
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

public fun create_boards(
    _: &AdminCap,
    week_anchor_ms: u64,
    cycle_end_ms: u64,
    max_score: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OperatorCap, ResultSignerCap, ModeratorCap) {
    let now = clock.timestamp_ms();
    assert!(max_score > 0, EZeroAmount);
    assert!(week_anchor_ms <= now, EBadAnchor);
    assert!(cycle_end_ms == 0 || cycle_end_ms > now, EBadCycleEnd);
    let id = object::new(ctx);
    let boards_id = object::uid_to_inner(&id);
    let op = OperatorCap { id: object::new(ctx), boards_id };
    let signer = ResultSignerCap { id: object::new(ctx), boards_id };
    let moderator = ModeratorCap { id: object::new(ctx), boards_id };
    let boards = Boards {
        id,
        version: VERSION,
        paused: false,
        place_points: vector[10, 7, 5, 3, 3, 3, 3, 3, 3, 3],
        participation_points: 1,
        review_delay_ms: 24 * HOUR_MS,
        week_anchor_ms,
        cycle_end_ms,
        max_score,
        operator_cap_id: object::id(&op),
        signer_cap_id: object::id(&signer),
        moderator_cap_ids: vector[object::id(&moderator)],
        banks: vec_map::empty(),
        weeks: table::new(ctx),
        first_week: U64_MAX,
        players: table::new(ctx),
        player_list: vector[],
        scan_pos: 0,
        scan_top: vector[],
        scan_done: false,
    };
    event::emit(BoardsCreated { boards_id, week_anchor_ms, cycle_end_ms, max_score });
    transfer::share_object(boards);
    (op, signer, moderator)
}

public fun create_bank<T>(_: &AdminCap, boards: &mut Boards, owner: address, price: u64, clock: &Clock, ctx: &mut TxContext): ID {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(price > 0, EZeroAmount);
    let key = type_name::with_defining_ids<T>();
    assert!(!boards.banks.contains(&key), EBankExists);
    let boards_id = object::id(boards);
    let bank = Bank<T> {
        id: object::new(ctx),
        version: VERSION,
        boards_id,
        paused: false,
        owner,
        price,
        split_bps: vector[5000, 3000, 2000],
        week_shares_bps: vector[5000, 3000, 2000],
        cycle_shares_bps: vector[4000, 2500, 1500, 1200, 800],
        week_bank: balance::zero(),
        bank_week: week_of(boards, clock.timestamp_ms()),
        closed_bank: balance::zero(),
        cycle_bank: balance::zero(),
        paid_weeks: table::new(ctx),
        cycle_paid: false,
    };
    let bank_id = object::id(&bank);
    boards.banks.insert(key, bank_id);
    event::emit(BankCreated { boards_id, bank_id, coin_type: coin_type<T>(), owner, price });
    transfer::share_object(bank);
    bank_id
}

public fun pay_attempt<T>(bank: &mut Bank<T>, boards: &Boards, payment: Coin<T>, run_nonce: vector<u8>, clock: &Clock, ctx: &mut TxContext) {
    check_pair(bank, boards);
    assert!(!boards.paused && !bank.paused, EPaused);
    let now = clock.timestamp_ms();
    assert!(now < cycle_end_or_max(boards), ECycleEnded);
    assert!(run_nonce.length() == NONCE_LEN, ENonceLength);
    let amount = payment.value();
    assert!(amount == bank.price, EWrongPrice);
    roll(bank, boards, now);
    let to_week = mul_bps(amount, *bank.split_bps.borrow(0));
    let to_cycle = mul_bps(amount, *bank.split_bps.borrow(1));
    let to_owner = amount - to_week - to_cycle;
    let mut bal = payment.into_balance();
    bank.week_bank.join(bal.split(to_week));
    bank.cycle_bank.join(bal.split(to_cycle));
    if (to_owner > 0) transfer::public_transfer(coin::from_balance(bal, ctx), bank.owner) else bal.destroy_zero();
    event::emit(AttemptPaid {
        boards_id: bank.boards_id,
        bank_id: object::id(bank),
        coin_type: coin_type<T>(),
        payer: ctx.sender(),
        run_nonce,
        amount,
        week: bank.bank_week,
        to_week,
        to_cycle,
        to_owner,
    });
}

public fun fund_cycle<T>(bank: &mut Bank<T>, coin: Coin<T>, ctx: &mut TxContext) {
    assert!(bank.version == VERSION, EWrongVersion);
    assert!(!bank.cycle_paid, ECycleEnded);
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);
    bank.cycle_bank.join(coin.into_balance());
    event::emit(CycleFunded { bank_id: object::id(bank), coin_type: coin_type<T>(), funder: ctx.sender(), amount, cycle_bank: bank.cycle_bank.value() });
}

public fun set_paused(boards: &mut Boards, _: &AdminCap, paused: bool) {
    assert!(boards.version == VERSION, EWrongVersion);
    boards.paused = paused;
    changed(object::id(boards), b"paused");
}

public fun set_review_delay_ms(boards: &mut Boards, _: &AdminCap, ms: u64) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(ms >= HOUR_MS && ms <= 168 * HOUR_MS, EBadDelay);
    boards.review_delay_ms = ms;
    changed(object::id(boards), b"review_delay_ms");
}

public fun set_league_points(boards: &mut Boards, _: &AdminCap, places: vector<u64>, participation: u64) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(places.length() >= 1 && places.length() <= BOARD_SIZE, EBadLeague);
    boards.place_points = places;
    boards.participation_points = participation;
    changed(object::id(boards), b"league_points");
}

public fun set_max_score(boards: &mut Boards, _: &AdminCap, max_score: u64) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(max_score > 0, EZeroAmount);
    boards.max_score = max_score;
    changed(object::id(boards), b"max_score");
}

public fun set_cycle_end_ms(boards: &mut Boards, _: &AdminCap, ms: u64, clock: &Clock) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(ms > clock.timestamp_ms() && boards.scan_pos == 0 && !boards.scan_done, EBadCycleEnd);
    assert!(!last_week_finalized(boards), EBadCycleEnd);
    boards.cycle_end_ms = ms;
    changed(object::id(boards), b"cycle_end_ms");
}

public fun set_cycle_end_now(boards: &mut Boards, _: &AdminCap, clock: &Clock) {
    assert!(boards.version == VERSION, EWrongVersion);
    let now = clock.timestamp_ms();
    assert!(now < cycle_end_or_max(boards) && boards.scan_pos == 0 && !boards.scan_done, EBadCycleEnd);
    boards.cycle_end_ms = now;
    changed(object::id(boards), b"cycle_end_ms");
}

public fun rotate_operator(boards: &mut Boards, _: &AdminCap, ctx: &mut TxContext): OperatorCap {
    assert!(boards.version == VERSION, EWrongVersion);
    let cap = OperatorCap { id: object::new(ctx), boards_id: object::id(boards) };
    boards.operator_cap_id = object::id(&cap);
    event::emit(CapRotated { boards_id: object::id(boards), kind: b"operator", cap_id: object::id(&cap) });
    cap
}

public fun rotate_signer(boards: &mut Boards, _: &AdminCap, ctx: &mut TxContext): ResultSignerCap {
    assert!(boards.version == VERSION, EWrongVersion);
    let cap = ResultSignerCap { id: object::new(ctx), boards_id: object::id(boards) };
    boards.signer_cap_id = object::id(&cap);
    event::emit(CapRotated { boards_id: object::id(boards), kind: b"signer", cap_id: object::id(&cap) });
    cap
}

public fun mint_moderator(boards: &mut Boards, _: &AdminCap, ctx: &mut TxContext): ModeratorCap {
    assert!(boards.version == VERSION, EWrongVersion);
    let cap = ModeratorCap { id: object::new(ctx), boards_id: object::id(boards) };
    boards.moderator_cap_ids.push_back(object::id(&cap));
    event::emit(CapRotated { boards_id: object::id(boards), kind: b"moderator", cap_id: object::id(&cap) });
    cap
}

public fun revoke_moderator(boards: &mut Boards, _: &AdminCap, cap_id: ID) {
    assert!(boards.version == VERSION, EWrongVersion);
    let (found, i) = boards.moderator_cap_ids.index_of(&cap_id);
    assert!(found, ENotFound);
    boards.moderator_cap_ids.remove(i);
    event::emit(CapRotated { boards_id: object::id(boards), kind: b"moderator_revoked", cap_id });
}

public fun set_bank_paused<T>(bank: &mut Bank<T>, _: &AdminCap, paused: bool) {
    assert!(bank.version == VERSION, EWrongVersion);
    bank.paused = paused;
    changed(object::id(bank), b"paused");
}

public fun set_price<T>(bank: &mut Bank<T>, _: &AdminCap, price: u64) {
    assert!(bank.version == VERSION, EWrongVersion);
    assert!(price > 0, EZeroAmount);
    bank.price = price;
    changed(object::id(bank), b"price");
}

public fun set_split_bps<T>(bank: &mut Bank<T>, _: &AdminCap, split: vector<u64>) {
    assert!(bank.version == VERSION, EWrongVersion);
    assert!(split.length() == 3 && sum(&split) == BPS, EBadSplit);
    bank.split_bps = split;
    changed(object::id(bank), b"split_bps");
}

public fun set_payout_shares<T>(bank: &mut Bank<T>, _: &AdminCap, week: vector<u64>, cycle: vector<u64>) {
    assert!(bank.version == VERSION, EWrongVersion);
    assert!(valid_shares(&week) && valid_shares(&cycle), EBadShares);
    bank.week_shares_bps = week;
    bank.cycle_shares_bps = cycle;
    changed(object::id(bank), b"payout_shares");
}

public fun set_owner<T>(bank: &mut Bank<T>, _: &AdminCap, owner: address) {
    assert!(bank.version == VERSION, EWrongVersion);
    bank.owner = owner;
    changed(object::id(bank), b"owner");
}

public fun is_paused(boards: &Boards): bool { boards.paused }
public fun cycle_end_ms(boards: &Boards): u64 { boards.cycle_end_ms }
public fun operator_cap_id(boards: &Boards): ID { boards.operator_cap_id }
public fun signer_cap_id(boards: &Boards): ID { boards.signer_cap_id }
public fun is_moderator(boards: &Boards, cap_id: ID): bool { boards.moderator_cap_ids.contains(&cap_id) }
public fun week_of_ms(boards: &Boards, ms: u64): u64 { week_of(boards, ms) }
public fun has_bank<T>(boards: &Boards): bool { boards.banks.contains(&type_name::with_defining_ids<T>()) }

public fun bank_of<T>(boards: &Boards): ID {
    let key = type_name::with_defining_ids<T>();
    assert!(boards.banks.contains(&key), ENotFound);
    *boards.banks.get(&key)
}

public fun price<T>(bank: &Bank<T>): u64 { bank.price }
public fun week_bank<T>(bank: &Bank<T>): u64 { bank.week_bank.value() }
public fun closed_bank<T>(bank: &Bank<T>): u64 { bank.closed_bank.value() }
public fun cycle_bank<T>(bank: &Bank<T>): u64 { bank.cycle_bank.value() }
public fun bank_week<T>(bank: &Bank<T>): u64 { bank.bank_week }
public fun bank_paused<T>(bank: &Bank<T>): bool { bank.paused }
public fun owner<T>(bank: &Bank<T>): address { bank.owner }
public fun boards_id<T>(bank: &Bank<T>): ID { bank.boards_id }

fun coin_type<T>(): String { type_name::with_defining_ids<T>().into_string() }

fun check_pair<T>(bank: &Bank<T>, boards: &Boards) {
    assert!(bank.version == VERSION && boards.version == VERSION, EWrongVersion);
    assert!(bank.boards_id == object::id(boards), EWrongBoards);
}

fun week_of(boards: &Boards, ms: u64): u64 { (ms - boards.week_anchor_ms) / WEEK_MS }

fun week_start(boards: &Boards, week: u64): u64 { boards.week_anchor_ms + week * WEEK_MS }

fun week_end(boards: &Boards, week: u64): u64 { boards.week_anchor_ms + (week + 1) * WEEK_MS }

fun cycle_end_or_max(boards: &Boards): u64 { if (boards.cycle_end_ms == 0) U64_MAX else boards.cycle_end_ms }

fun roll<T>(bank: &mut Bank<T>, boards: &Boards, now: u64) {
    let w = week_of(boards, now);
    if (w > bank.bank_week) {
        let all = bank.week_bank.withdraw_all();
        bank.closed_bank.join(all);
        bank.bank_week = w;
    }
}

fun mul_bps(v: u64, bps: u64): u64 { (((v as u128) * (bps as u128)) / (BPS as u128)) as u64 }

fun sum(v: &vector<u64>): u64 {
    let mut s = 0;
    let mut i = 0;
    while (i < v.length()) {
        s = s + *v.borrow(i);
        i = i + 1;
    };
    s
}

fun valid_shares(v: &vector<u64>): bool { v.length() >= 1 && v.length() <= MAX_SHARES && sum(v) == BPS }

fun last_week_finalized(boards: &Boards): bool {
    if (boards.cycle_end_ms <= boards.week_anchor_ms) return false;
    let last = week_of(boards, boards.cycle_end_ms - 1);
    boards.weeks.contains(last) && boards.weeks.borrow(last).finalized
}

fun min(a: u64, b: u64): u64 { if (a < b) a else b }

fun changed(object_id: ID, field: vector<u8>) {
    event::emit(ConfigChanged { object_id, field });
}

public struct ResultRecorded has copy, drop {
    boards_id: ID,
    week: u64,
    player: address,
    character_id: ID,
    score: u64,
    replay_hash: vector<u8>,
    place: u64,
    participation: bool,
}

public struct ResultRemoved has copy, drop { boards_id: ID, week: u64, player: address, moderator_cap_id: ID }

public struct WeekFinalized has copy, drop { boards_id: ID, week: u64, players: vector<address>, points: vector<u64> }

fun period_end(boards: &Boards, week: u64): u64 { min(week_end(boards, week), cycle_end_or_max(boards)) }

fun board_mut(boards: &mut Boards, week: u64, ctx: &mut TxContext): &mut WeekBoard {
    if (!boards.weeks.contains(week)) {
        let participation = boards.participation_points;
        boards.weeks.add(week, WeekBoard {
            top: vector[],
            participants: table::new(ctx),
            disqualified: table::new(ctx),
            finalized: false,
            participation,
        });
    };
    boards.weeks.borrow_mut(week)
}

fun insert_top(board: &mut WeekBoard, e: Entry): u64 {
    let mut i = 0;
    while (i < board.top.length()) {
        if (board.top.borrow(i).player == e.player) {
            if (e.score <= board.top.borrow(i).score) return 0;
            board.top.remove(i);
            break
        };
        i = i + 1;
    };
    let mut pos = 0;
    while (pos < board.top.length() && board.top.borrow(pos).score >= e.score) pos = pos + 1;
    if (pos >= BOARD_SIZE) return 0;
    board.top.insert(e, pos);
    if (board.top.length() > BOARD_SIZE) {
        board.top.pop_back();
    };
    pos + 1
}

fun touch_player(boards: &mut Boards, player: address, add_points: u64, score: u64, now: u64): bool {
    if (!boards.players.contains(player)) {
        boards.players.add(player, PlayerCycle { points: 0, best: 0, best_at_ms: 0 });
        boards.player_list.push_back(player);
    };
    let p = boards.players.borrow_mut(player);
    p.points = p.points + add_points;
    if (p.best_at_ms == 0 || score > p.best) {
        p.best = score;
        p.best_at_ms = now;
        true
    } else false
}

public fun record_result(
    boards: &mut Boards,
    cap: &ResultSignerCap,
    week: u64,
    player: address,
    character_id: ID,
    score: u64,
    replay_hash: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(object::id(cap) == boards.signer_cap_id, ENotSigner);
    assert!(replay_hash.length() == HASH_LEN, EHashLength);
    assert!(score <= boards.max_score, EScoreTooHigh);
    let now = clock.timestamp_ms();
    let current = week_of(boards, now);
    let open = week <= current && now < period_end(boards, week) + boards.review_delay_ms;
    assert!(open && week_start(boards, week) < cycle_end_or_max(boards), EWeekClosed);
    let boards_id = object::id(boards);
    let board = board_mut(boards, week, ctx);
    assert!(!board.finalized, EWeekClosed);
    let participation = board.participation;
    assert!(!board.disqualified.contains(player), EDisqualified);
    let first = !board.participants.contains(player);
    let mut changed = first;
    if (first) board.participants.add(player, score)
    else {
        let b = board.participants.borrow_mut(player);
        if (score > *b) {
            *b = score;
            changed = true;
        };
    };
    let place = insert_top(board, Entry { player, character_id, score, at_ms: now, replay_hash });
    let best = touch_player(boards, player, if (first) participation else 0, score, now);
    if (week < boards.first_week) boards.first_week = week;
    assert!(changed || place > 0 || best, ENothingChanged);
    event::emit(ResultRecorded { boards_id, week, player, character_id, score, replay_hash, place, participation: first });
}

public fun remove_result(boards: &mut Boards, cap: &ModeratorCap, week: u64, player: address, clock: &Clock, ctx: &mut TxContext) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(boards.moderator_cap_ids.contains(&object::id(cap)), ENotModerator);
    let now = clock.timestamp_ms();
    assert!(week <= week_of(boards, now) && week_start(boards, week) < cycle_end_or_max(boards), EWeekClosed);
    assert!(now < period_end(boards, week) + boards.review_delay_ms, EReviewClosed);
    let boards_id = object::id(boards);
    let board = board_mut(boards, week, ctx);
    assert!(!board.finalized, EReviewClosed);
    let participation = board.participation;
    let mut i = 0;
    while (i < board.top.length()) {
        if (board.top.borrow(i).player == player) {
            board.top.remove(i);
            break
        };
        i = i + 1;
    };
    let had = board.participants.contains(player);
    if (had) {
        board.participants.remove(player);
    };
    if (!board.disqualified.contains(player)) board.disqualified.add(player, true);
    if (had && boards.players.contains(player)) {
        let p = boards.players.borrow_mut(player);
        p.points = if (p.points >= participation) p.points - participation else 0;
    };
    event::emit(ResultRemoved { boards_id, week, player, moderator_cap_id: object::id(cap) });
}

public fun finalize_week(boards: &mut Boards, cap: &OperatorCap, week: u64, clock: &Clock, ctx: &mut TxContext) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(object::id(cap) == boards.operator_cap_id, ENotOperator);
    let now = clock.timestamp_ms();
    assert!(week <= week_of(boards, now) && week_start(boards, week) < cycle_end_or_max(boards), ETooEarly);
    assert!(now >= period_end(boards, week) + boards.review_delay_ms, ETooEarly);
    let places = boards.place_points;
    let boards_id = object::id(boards);
    let (top, participation) = {
        let board = board_mut(boards, week, ctx);
        assert!(!board.finalized, EAlreadyFinalized);
        board.finalized = true;
        (board.top, board.participation)
    };
    let mut players = vector[];
    let mut pts = vector[];
    let mut i = 0;
    while (i < top.length()) {
        let who = top.borrow(i).player;
        let place_pts = if (i < places.length()) *places.borrow(i) else participation;
        let extra = if (place_pts > participation) place_pts - participation else 0;
        let p = boards.players.borrow_mut(who);
        p.points = p.points + extra;
        players.push_back(who);
        pts.push_back(place_pts);
        i = i + 1;
    };
    event::emit(WeekFinalized { boards_id, week, players, points: pts });
}

public fun top_players(boards: &Boards, week: u64): vector<address> {
    if (!boards.weeks.contains(week)) return vector[];
    let top = &boards.weeks.borrow(week).top;
    let mut out = vector[];
    let mut i = 0;
    while (i < top.length()) {
        out.push_back(top.borrow(i).player);
        i = i + 1;
    };
    out
}

public fun top_scores(boards: &Boards, week: u64): vector<u64> {
    if (!boards.weeks.contains(week)) return vector[];
    let top = &boards.weeks.borrow(week).top;
    let mut out = vector[];
    let mut i = 0;
    while (i < top.length()) {
        out.push_back(top.borrow(i).score);
        i = i + 1;
    };
    out
}

public fun points_of(boards: &Boards, player: address): u64 {
    if (boards.players.contains(player)) boards.players.borrow(player).points else 0
}

public fun best_of(boards: &Boards, player: address): u64 {
    if (boards.players.contains(player)) boards.players.borrow(player).best else 0
}

public fun is_finalized(boards: &Boards, week: u64): bool {
    boards.weeks.contains(week) && boards.weeks.borrow(week).finalized
}

public struct WeekPaid has copy, drop {
    boards_id: ID,
    bank_id: ID,
    coin_type: String,
    week: u64,
    winners: vector<address>,
    amounts: vector<u64>,
    bank_before: u64,
}

public struct CyclePaid has copy, drop {
    boards_id: ID,
    bank_id: ID,
    coin_type: String,
    winners: vector<address>,
    amounts: vector<u64>,
    bank_before: u64,
}

public fun payout_week<T>(bank: &mut Bank<T>, boards: &Boards, cap: &OperatorCap, week: u64, clock: &Clock, ctx: &mut TxContext) {
    check_pair(bank, boards);
    assert!(!boards.paused && !bank.paused, EPaused);
    assert!(object::id(cap) == boards.operator_cap_id, ENotOperator);
    assert!(boards.weeks.contains(week) && boards.weeks.borrow(week).finalized, ENotFinalized);
    assert!(!bank.paid_weeks.contains(week), EAlreadyPaid);
    let mut w = boards.first_week;
    while (w < week) {
        if (boards.weeks.contains(w)) {
            assert!(boards.weeks.borrow(w).finalized && bank.paid_weeks.contains(w), ENotPaidOut);
        };
        w = w + 1;
    };
    bank.paid_weeks.add(week, true);
    let now = clock.timestamp_ms();
    roll(bank, boards, now);
    if (boards.cycle_end_ms != 0 && now >= boards.cycle_end_ms && week == week_of(boards, boards.cycle_end_ms - 1)) {
        let all = bank.week_bank.withdraw_all();
        bank.closed_bank.join(all);
    };
    let top = boards.weeks.borrow(week).top;
    let shares = bank.week_shares_bps;
    let bank_before = bank.closed_bank.value();
    let n = min(top.length(), shares.length());
    let mut winners = vector[];
    let mut amounts = vector[];
    let mut i = 0;
    while (i < n) {
        let amount = mul_bps(bank_before, *shares.borrow(i));
        let to = top.borrow(i).player;
        if (amount > 0) transfer::public_transfer(coin::take(&mut bank.closed_bank, amount, ctx), to);
        winners.push_back(to);
        amounts.push_back(amount);
        i = i + 1;
    };
    event::emit(WeekPaid { boards_id: bank.boards_id, bank_id: object::id(bank), coin_type: coin_type<T>(), week, winners, amounts, bank_before });
}

fun better(x: &PlayerCycle, y: &PlayerCycle): bool {
    x.points > y.points || (x.points == y.points && (x.best > y.best || (x.best == y.best && x.best_at_ms < y.best_at_ms)))
}

public fun scan_cycle(boards: &mut Boards, cap: &OperatorCap, max_items: u64, clock: &Clock) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(object::id(cap) == boards.operator_cap_id, ENotOperator);
    assert!(boards.cycle_end_ms != 0, ECycleEndUnset);
    assert!(clock.timestamp_ms() >= boards.cycle_end_ms + boards.review_delay_ms, ETooEarly);
    assert!(cycle_weeks_finalized(boards), ENotFinalized);
    let mut done = 0;
    while (boards.scan_pos < boards.player_list.length() && done < max_items) {
        let who = *boards.player_list.borrow(boards.scan_pos);
        let pc = *boards.players.borrow(who);
        if (pc.points > 0) {
            let mut pos = 0;
            while (pos < boards.scan_top.length() && !better(&pc, boards.players.borrow(*boards.scan_top.borrow(pos)))) pos = pos + 1;
            if (pos < MAX_SHARES) {
                boards.scan_top.insert(who, pos);
                if (boards.scan_top.length() > MAX_SHARES) {
                    boards.scan_top.pop_back();
                };
            };
        };
        boards.scan_pos = boards.scan_pos + 1;
        done = done + 1;
    };
    if (boards.scan_pos == boards.player_list.length()) boards.scan_done = true;
}

public fun payout_cycle<T>(bank: &mut Bank<T>, boards: &Boards, cap: &OperatorCap, ctx: &mut TxContext) {
    check_pair(bank, boards);
    assert!(!boards.paused && !bank.paused, EPaused);
    assert!(object::id(cap) == boards.operator_cap_id, ENotOperator);
    assert!(boards.cycle_end_ms != 0, ECycleEndUnset);
    assert!(boards.scan_done, EScanNotDone);
    assert!(!bank.cycle_paid, EAlreadyPaid);
    bank.cycle_paid = true;
    let shares = bank.cycle_shares_bps;
    let n = min(boards.scan_top.length(), shares.length());
    let bank_before = bank.cycle_bank.value();
    let mut winners = vector[];
    let mut amounts = vector[];
    let mut i = 0;
    while (i < n) {
        let to = *boards.scan_top.borrow(i);
        let amount = mul_bps(bank_before, *shares.borrow(i));
        if (amount > 0) transfer::public_transfer(coin::take(&mut bank.cycle_bank, amount, ctx), to);
        winners.push_back(to);
        amounts.push_back(amount);
        i = i + 1;
    };
    event::emit(CyclePaid { boards_id: bank.boards_id, bank_id: object::id(bank), coin_type: coin_type<T>(), winners, amounts, bank_before });
}

public fun is_week_paid<T>(bank: &Bank<T>, week: u64): bool { bank.paid_weeks.contains(week) }
public fun cycle_paid<T>(bank: &Bank<T>): bool { bank.cycle_paid }
public fun scan_done(boards: &Boards): bool { boards.scan_done }
public fun scan_top(boards: &Boards): vector<address> { boards.scan_top }

fun cycle_weeks_finalized(boards: &Boards): bool {
    let last = week_of(boards, boards.cycle_end_ms - 1);
    let mut w = boards.first_week;
    while (w <= last) {
        if (boards.weeks.contains(w) && !boards.weeks.borrow(w).finalized) return false;
        w = w + 1;
    };
    true
}

public struct CarriedOver has copy, drop { from_bank: ID, to_bank: ID, coin_type: String, amount: u64 }

public fun carry_over<T>(old_bank: &mut Bank<T>, old_boards: &Boards, new_bank: &mut Bank<T>, _: &AdminCap) {
    check_pair(old_bank, old_boards);
    assert!(new_bank.version == VERSION, EWrongVersion);
    assert!(new_bank.boards_id != old_bank.boards_id, EWrongBoards);
    assert!(!new_bank.cycle_paid, ECycleEnded);
    assert!(old_bank.cycle_paid, ENotPaidOut);
    let last = week_of(old_boards, old_boards.cycle_end_ms - 1);
    assert!(old_bank.paid_weeks.contains(last), ENotPaidOut);
    let mut w = old_boards.first_week;
    while (w <= last) {
        if (old_boards.weeks.contains(w) && old_boards.weeks.borrow(w).finalized) {
            assert!(old_bank.paid_weeks.contains(w), ENotPaidOut);
        };
        w = w + 1;
    };
    let mut all = old_bank.week_bank.withdraw_all();
    all.join(old_bank.closed_bank.withdraw_all());
    all.join(old_bank.cycle_bank.withdraw_all());
    let amount = all.value();
    assert!(amount > 0, EZeroAmount);
    new_bank.cycle_bank.join(all);
    event::emit(CarriedOver { from_bank: object::id(old_bank), to_bank: object::id(new_bank), coin_type: coin_type<T>(), amount });
}

public struct MarathonBadge has key {
    id: UID,
    boards_id: ID,
    week: u64,
    place: u64,
    distance: u64,
}

public struct MarathonKey has copy, drop, store { week: u64, player: address }

public struct MarathonBadgeMinted has copy, drop { boards_id: ID, week: u64, player: address, place: u64, badge_id: ID }

public fun mint_marathon_badge(boards: &mut Boards, cap: &OperatorCap, week: u64, player: address, place: u64, distance: u64, clock: &Clock, ctx: &mut TxContext) {
    assert!(boards.version == VERSION, EWrongVersion);
    assert!(object::id(cap) == boards.operator_cap_id, ENotOperator);
    assert!(!boards.paused, EPaused);
    assert!(place >= 1 && place <= 20, EBadPlace);
    assert!(week < week_of(boards, clock.timestamp_ms()), EWeekNotOver);
    let key = MarathonKey { week, player };
    assert!(!dynamic_field::exists(&boards.id, key), EMarathonMinted);
    dynamic_field::add(&mut boards.id, key, true);
    let badge = MarathonBadge { id: object::new(ctx), boards_id: object::id(boards), week, place, distance };
    event::emit(MarathonBadgeMinted { boards_id: object::id(boards), week, player, place, badge_id: object::id(&badge) });
    transfer::transfer(badge, player);
}

public fun marathon_minted(boards: &Boards, week: u64, player: address): bool {
    dynamic_field::exists(&boards.id, MarathonKey { week, player })
}

public fun marathon_week(b: &MarathonBadge): u64 { b.week }

public fun marathon_place(b: &MarathonBadge): u64 { b.place }

public fun marathon_distance(b: &MarathonBadge): u64 { b.distance }

public fun marathon_boards_id(b: &MarathonBadge): ID { b.boards_id }

#[test_only]
public fun first_week_for_testing(boards: &Boards): u64 { boards.first_week }

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx) }
