module academy_gas::gas_budget;

use academy_core::core::{AcademyAdminCap, RewardTicket};
use sui::{balance::{Self, Balance}, coin::{Self, Coin}, derived_object, event, sui::SUI};

const VERSION: u64 = 1;

const MAX_CHARGE_CEILING: u64 = 50_000_000;

const DEFAULT_MAX_CHARGE: u64 = 20_000_000;

#[error(code = 230)]
const EWrongVersion: vector<u8> = b"Gas config or budget version does not match the package version";
#[error(code = 231)]
const ENotAcademyAdmin: vector<u8> = b"AcademyAdminCap belongs to another academy than the gas budget";
#[error(code = 232)]
const EBudgetExists: vector<u8> = b"The academy already has a gas budget";
#[error(code = 233)]
const EZeroAmount: vector<u8> = b"Amount must be greater than zero";
#[error(code = 234)]
const EWithdrawExceedsBalance: vector<u8> = b"Withdraw amount exceeds the gas budget balance";
#[error(code = 235)]
const ESponsorNotSet: vector<u8> = b"Gas sponsor is not configured";
#[error(code = 236)]
const ENotSponsored: vector<u8> = b"Transaction is not sponsored by the configured gas sponsor";
#[error(code = 237)]
const EWrongAcademy: vector<u8> = b"Reward ticket belongs to another academy than the gas budget";
#[error(code = 238)]
const EChargeAboveCap: vector<u8> = b"Charge exceeds the per-claim limit";
#[error(code = 239)]
const EAlreadyChargedInTx: vector<u8> = b"Gas budget is already charged in this transaction";
#[error(code = 240)]
const EMaxChargeOutOfRange: vector<u8> = b"Per-claim limit must be within 1 and the hard ceiling";
#[error(code = 241)]
const ENothingToCollect: vector<u8> = b"Gas budget has nothing due to the sponsor";
#[error(code = 242)]
const EAlreadyMigrated: vector<u8> = b"Object is already at the current package version";

public struct GasAdminCap has key, store { id: UID }

public struct GasConfig has key {
    id: UID,
    version: u64,
    sponsor: address,
    max_charge_per_claim: u64,
}

public struct BudgetKey has copy, drop, store { academy_id: ID }

public struct GasBudget has key {
    id: UID,
    version: u64,
    academy_id: ID,
    balance: Balance<SUI>,
    sponsor_due: Balance<SUI>,
    charged_total: u64,
    charges: u64,
    last_charge_digest: vector<u8>,
    paused: bool,
}

public struct GasConfigChanged has copy, drop { sponsor: address, max_charge_per_claim: u64 }

public struct BudgetCreated has copy, drop { budget_id: ID, academy_id: ID }

public struct BudgetFunded has copy, drop {
    budget_id: ID,
    academy_id: ID,
    funder: address,
    amount: u64,
    balance: u64,
}

public struct BudgetWithdrawn has copy, drop {
    budget_id: ID,
    academy_id: ID,
    amount: u64,
    balance: u64,
}

public struct BudgetPaused has copy, drop { budget_id: ID, academy_id: ID, paused: bool }

public struct GasCharged has copy, drop {
    budget_id: ID,
    academy_id: ID,
    quest_id: ID,
    recipient: address,
    requested: u64,
    charged: u64,
    balance_after: u64,
}

public struct DueCollected has copy, drop {
    budget_id: ID,
    academy_id: ID,
    sponsor: address,
    amount: u64,
}

fun init(ctx: &mut TxContext) {
    transfer::share_object(GasConfig {
        id: object::new(ctx),
        version: VERSION,
        sponsor: @0x0,
        max_charge_per_claim: DEFAULT_MAX_CHARGE,
    });
    transfer::public_transfer(GasAdminCap { id: object::new(ctx) }, ctx.sender());
}

public fun set_sponsor(config: &mut GasConfig, _: &GasAdminCap, sponsor: address) {
    assert!(config.version == VERSION, EWrongVersion);
    config.sponsor = sponsor;
    emit_config_changed(config);
}

public fun set_max_charge(config: &mut GasConfig, _: &GasAdminCap, max_charge_per_claim: u64) {
    assert!(config.version == VERSION, EWrongVersion);
    assert!(
        max_charge_per_claim > 0 && max_charge_per_claim <= MAX_CHARGE_CEILING,
        EMaxChargeOutOfRange,
    );
    config.max_charge_per_claim = max_charge_per_claim;
    emit_config_changed(config);
}

public fun migrate_config(config: &mut GasConfig, _: &GasAdminCap) {
    assert!(config.version < VERSION, EAlreadyMigrated);
    config.version = VERSION;
}

public fun create_budget(config: &mut GasConfig, cap: &AcademyAdminCap, _ctx: &mut TxContext): ID {
    assert!(config.version == VERSION, EWrongVersion);
    let academy_id = cap.admin_academy_id();
    let key = BudgetKey { academy_id };
    assert!(!derived_object::exists(&config.id, key), EBudgetExists);
    let budget = GasBudget {
        id: derived_object::claim(&mut config.id, key),
        version: VERSION,
        academy_id,
        balance: balance::zero(),
        sponsor_due: balance::zero(),
        charged_total: 0,
        charges: 0,
        last_charge_digest: vector[],
        paused: false,
    };
    let budget_id = object::id(&budget);
    event::emit(BudgetCreated { budget_id, academy_id });
    transfer::share_object(budget);
    budget_id
}

public fun deposit(budget: &mut GasBudget, coin: Coin<SUI>, ctx: &mut TxContext) {
    assert!(budget.version == VERSION, EWrongVersion);
    let amount = coin.value();
    assert!(amount > 0, EZeroAmount);
    budget.balance.join(coin.into_balance());
    event::emit(BudgetFunded {
        budget_id: object::id(budget),
        academy_id: budget.academy_id,
        funder: ctx.sender(),
        amount,
        balance: budget.balance.value(),
    });
}

public fun withdraw(
    budget: &mut GasBudget,
    cap: &AcademyAdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert_lead(budget, cap);
    assert!(amount > 0, EZeroAmount);
    assert!(amount <= budget.balance.value(), EWithdrawExceedsBalance);
    take_for_lead(budget, amount, ctx)
}

public fun withdraw_all(budget: &mut GasBudget, cap: &AcademyAdminCap, ctx: &mut TxContext): Coin<SUI> {
    assert_lead(budget, cap);
    let amount = budget.balance.value();
    assert!(amount > 0, EZeroAmount);
    take_for_lead(budget, amount, ctx)
}

public fun set_paused(budget: &mut GasBudget, cap: &AcademyAdminCap, paused: bool) {
    assert_lead(budget, cap);
    budget.paused = paused;
    event::emit(BudgetPaused { budget_id: object::id(budget), academy_id: budget.academy_id, paused });
}

public fun migrate_budget(budget: &mut GasBudget, cap: &AcademyAdminCap) {
    assert!(cap.admin_academy_id() == budget.academy_id, ENotAcademyAdmin);
    assert!(budget.version < VERSION, EAlreadyMigrated);
    budget.version = VERSION;
}

public fun charge(
    config: &GasConfig,
    budget: &mut GasBudget,
    rt: &RewardTicket,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(config.version == VERSION, EWrongVersion);
    assert!(budget.version == VERSION, EWrongVersion);
    assert!(config.sponsor != @0x0, ESponsorNotSet);
    assert!(ctx.sponsor() == option::some(config.sponsor), ENotSponsored);
    assert!(rt.reward_academy_id() == budget.academy_id, EWrongAcademy);
    assert!(amount > 0, EZeroAmount);
    assert!(amount <= config.max_charge_per_claim, EChargeAboveCap);
    assert!(ctx.digest() != &budget.last_charge_digest, EAlreadyChargedInTx);
    budget.last_charge_digest = *ctx.digest();

    let charged = if (budget.paused) 0 else amount.min(budget.balance.value());
    if (charged > 0) {
        budget.sponsor_due.join(budget.balance.split(charged));
        budget.charged_total = budget.charged_total + charged;
        budget.charges = budget.charges + 1;
    };
    event::emit(GasCharged {
        budget_id: object::id(budget),
        academy_id: budget.academy_id,
        quest_id: rt.reward_quest_id(),
        recipient: rt.reward_recipient(),
        requested: amount,
        charged,
        balance_after: budget.balance.value(),
    });
}

public fun collect(config: &GasConfig, budget: &mut GasBudget, ctx: &mut TxContext) {
    assert!(config.version == VERSION, EWrongVersion);
    assert!(budget.version == VERSION, EWrongVersion);
    assert!(config.sponsor != @0x0, ESponsorNotSet);
    let amount = budget.sponsor_due.value();
    assert!(amount > 0, ENothingToCollect);
    transfer::public_transfer(coin::take(&mut budget.sponsor_due, amount, ctx), config.sponsor);
    event::emit(DueCollected {
        budget_id: object::id(budget),
        academy_id: budget.academy_id,
        sponsor: config.sponsor,
        amount,
    });
}

public fun package_version(): u64 { VERSION }

public fun max_charge_ceiling(): u64 { MAX_CHARGE_CEILING }

public fun sponsor(config: &GasConfig): address { config.sponsor }

public fun max_charge_per_claim(config: &GasConfig): u64 { config.max_charge_per_claim }

public fun config_version(config: &GasConfig): u64 { config.version }

public fun budget_key(academy_id: ID): BudgetKey { BudgetKey { academy_id } }

public fun budget_id_for(config: &GasConfig, academy_id: ID): ID {
    derived_object::derive_address(object::id(config), BudgetKey { academy_id }).to_id()
}

public fun has_budget(config: &GasConfig, academy_id: ID): bool {
    derived_object::exists(&config.id, BudgetKey { academy_id })
}

public fun academy_id(budget: &GasBudget): ID { budget.academy_id }

public fun balance(budget: &GasBudget): u64 { budget.balance.value() }

public fun sponsor_due(budget: &GasBudget): u64 { budget.sponsor_due.value() }

public fun charged_total(budget: &GasBudget): u64 { budget.charged_total }

public fun charges(budget: &GasBudget): u64 { budget.charges }

public fun last_charge_digest(budget: &GasBudget): vector<u8> { budget.last_charge_digest }

public fun is_paused(budget: &GasBudget): bool { budget.paused }

public fun budget_version(budget: &GasBudget): u64 { budget.version }

fun assert_lead(budget: &GasBudget, cap: &AcademyAdminCap) {
    assert!(budget.version <= VERSION, EWrongVersion);
    assert!(cap.admin_academy_id() == budget.academy_id, ENotAcademyAdmin);
}

fun take_for_lead(budget: &mut GasBudget, amount: u64, ctx: &mut TxContext): Coin<SUI> {
    let coin = coin::take(&mut budget.balance, amount, ctx);
    event::emit(BudgetWithdrawn {
        budget_id: object::id(budget),
        academy_id: budget.academy_id,
        amount,
        balance: budget.balance.value(),
    });
    coin
}

fun emit_config_changed(config: &GasConfig) {
    event::emit(GasConfigChanged {
        sponsor: config.sponsor,
        max_charge_per_claim: config.max_charge_per_claim,
    });
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx) }

#[test_only]
public fun set_config_version_for_testing(config: &mut GasConfig, version: u64) {
    config.version = version;
}

#[test_only]
public fun set_budget_version_for_testing(budget: &mut GasBudget, version: u64) {
    budget.version = version;
}

#[test_only]
public fun new_gas_charged_for_testing(
    budget_id: ID,
    academy_id: ID,
    quest_id: ID,
    recipient: address,
    requested: u64,
    charged: u64,
    balance_after: u64,
): GasCharged {
    GasCharged { budget_id, academy_id, quest_id, recipient, requested, charged, balance_after }
}
