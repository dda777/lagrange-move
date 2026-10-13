module academy_rewards::coin_pool;

use academy_core::core::{Self, AcademyAdminCap, Requirement, RewardTicket};
use std::{internal, type_name::{Self, TypeName}};
use sui::{balance::{Self, Balance}, bcs, coin::{Self, Coin}, event};

const VERSION: u64 = 1;

#[error(code = 200)]
const EWrongVersion: vector<u8> = b"Coin pool version does not match the package version";
#[error(code = 201)]
const ENotAcademyAdmin: vector<u8> = b"AcademyAdminCap belongs to another academy than the pool";
#[error(code = 202)]
const EWrongPool: vector<u8> = b"Coin pool is not the one configured in the reward";
#[error(code = 203)]
const EWrongAcademy: vector<u8> = b"Coin pool belongs to another academy than the quest";
#[error(code = 204)]
const EPoolInsufficient: vector<u8> = b"Coin pool has not enough coins for a required reward";
#[error(code = 205)]
const EMaxClaimsReached: vector<u8> = b"Coin pool claim limit is reached for a required reward";
#[error(code = 206)]
const EZeroAmount: vector<u8> = b"Amount must be greater than zero";
#[error(code = 207)]
const EWithdrawExceedsBalance: vector<u8> = b"Withdraw amount exceeds the pool balance";
#[error(code = 208)]
const EAlreadyMigrated: vector<u8> = b"Coin pool is already at the current package version";

public struct CoinPool<phantom T> has key {
    id: UID,
    version: u64,
    academy_id: ID,
    balance: Balance<T>,
    max_claims: u64,
    claims: u64,
}

public struct CoinReward<phantom T> has drop {
    pool_id: ID,
    amount: u64,
    optional: bool,
}

public struct PoolCreated has copy, drop {
    pool_id: ID,
    academy_id: ID,
    coin_type: TypeName,
    max_claims: u64,
}

public struct PoolFunded has copy, drop { pool_id: ID, funder: address, amount: u64, balance: u64 }

public struct PoolWithdrawn has copy, drop { pool_id: ID, amount: u64, balance: u64 }

public struct RewardSkipped has copy, drop {
    pool_id: ID,
    quest_id: ID,
    recipient: address,
    amount: u64,
}

public fun create<T>(cap: &AcademyAdminCap, max_claims: u64, ctx: &mut TxContext): ID {
    let pool = CoinPool<T> {
        id: object::new(ctx),
        version: VERSION,
        academy_id: cap.admin_academy_id(),
        balance: balance::zero(),
        max_claims,
        claims: 0,
    };
    let pool_id = object::id(&pool);
    event::emit(PoolCreated {
        pool_id,
        academy_id: pool.academy_id,
        coin_type: type_name::with_original_ids<T>(),
        max_claims,
    });
    transfer::share_object(pool);
    pool_id
}

public fun fund<T>(pool: &mut CoinPool<T>, coin: Coin<T>, ctx: &TxContext) {
    assert!(pool.version == VERSION, EWrongVersion);
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);
    pool.balance.join(coin.into_balance());
    event::emit(PoolFunded {
        pool_id: object::id(pool),
        funder: ctx.sender(),
        amount,
        balance: pool.balance.value(),
    });
}

public fun withdraw<T>(
    pool: &mut CoinPool<T>,
    cap: &AcademyAdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    assert_admin(pool, cap);
    assert!(amount <= pool.balance.value(), EWithdrawExceedsBalance);
    let coin = coin::take(&mut pool.balance, amount, ctx);
    event::emit(PoolWithdrawn { pool_id: object::id(pool), amount, balance: pool.balance.value() });
    coin
}

public fun migrate<T>(pool: &mut CoinPool<T>, cap: &AcademyAdminCap) {
    assert!(cap.admin_academy_id() == pool.academy_id, ENotAcademyAdmin);
    assert!(pool.version < VERSION, EAlreadyMigrated);
    pool.version = VERSION;
}

public fun package_version(): u64 { VERSION }

public fun requirement<T>(
    pool: &CoinPool<T>,
    cap: &AcademyAdminCap,
    amount: u64,
    optional: bool,
): Requirement {
    assert_admin(pool, cap);
    assert!(amount > 0, EZeroAmount);
    core::requirement(CoinReward<T> { pool_id: object::id(pool), amount, optional })
}

public fun pay<T>(rt: &mut RewardTicket, pool: &mut CoinPool<T>, ctx: &mut TxContext) {
    let (pool_id, amount, optional) = decode(rt.peek_reward<CoinReward<T>>());
    assert!(object::id(pool) == pool_id, EWrongPool);
    assert!(pool.version == VERSION, EWrongVersion);
    assert!(pool.academy_id == rt.reward_academy_id(), EWrongAcademy);

    let enough = pool.balance.value() >= amount;
    let under_limit = pool.max_claims == 0 || pool.claims < pool.max_claims;
    if (!enough || !under_limit) {
        assert!(optional || enough, EPoolInsufficient);
        assert!(optional, EMaxClaimsReached);
        rt.skip_optional_reward(internal::permit<CoinReward<T>>());
        event::emit(RewardSkipped {
            pool_id,
            quest_id: rt.reward_quest_id(),
            recipient: rt.reward_recipient(),
            amount,
        });
        return
    };

    let (_, recipient, _) = rt.take_reward(internal::permit<CoinReward<T>>());
    pool.claims = pool.claims + 1;
    transfer::public_transfer(coin::take(&mut pool.balance, amount, ctx), recipient);
    rt.record_payment(internal::permit<CoinReward<T>>(), amount);
}

public fun academy_id<T>(pool: &CoinPool<T>): ID { pool.academy_id }

public fun value<T>(pool: &CoinPool<T>): u64 { pool.balance.value() }

public fun max_claims<T>(pool: &CoinPool<T>): u64 { pool.max_claims }

public fun claims<T>(pool: &CoinPool<T>): u64 { pool.claims }

public fun version<T>(pool: &CoinPool<T>): u64 { pool.version }

fun assert_admin<T>(pool: &CoinPool<T>, cap: &AcademyAdminCap) {
    assert!(pool.version == VERSION, EWrongVersion);
    assert!(cap.admin_academy_id() == pool.academy_id, ENotAcademyAdmin);
}

fun decode(data: vector<u8>): (ID, u64, bool) {
    let mut r = bcs::new(data);
    let pool_id = object::id_from_address(r.peel_address());
    let amount = r.peel_u64();
    let optional = r.peel_bool();
    (pool_id, amount, optional)
}

#[test_only]
public fun set_version_for_testing<T>(pool: &mut CoinPool<T>, version: u64) {
    pool.version = version;
}
