#[test_only]
module academy_gas::gas_budget_tests;

use academy_core::core::{Self, Academy, AcademyAdminCap, Quest, RewardTicket};
use academy_gas::{gas_budget::{Self, GasAdminCap, GasBudget, GasConfig}, test_handlers};
use std::string::{String, utf8};
use sui::{coin::{Self, Coin}, event, sui::SUI, test_scenario::{Self as ts, Scenario}};

const PUBLISHER: address = @0xAD;
const SPONSOR: address = @0x5905;
const OTHER_SPONSOR: address = @0x5906;
const LEAD: address = @0xA1;
const OTHER_LEAD: address = @0xA2;
const FUNDER: address = @0xF1;
const PLAYER: address = @0xB1;
const PLAYER_2: address = @0xB2;

const FUNDED: u64 = 100_000_000;
const DEFAULT_MAX: u64 = 20_000_000;

fun tenant(): String { utf8(b"TEST") }

fun publish(s: &mut Scenario): ID {
    gas_budget::init_for_testing(s.ctx());
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared<GasConfig>();
    let cap = s.take_from_sender<GasAdminCap>();
    config.set_sponsor(&cap, SPONSOR);
    let config_id = object::id(&config);
    s.return_to_sender(cap);
    ts::return_shared(config);
    config_id
}

fun new_academy(s: &mut Scenario, lead: address): ID {
    s.next_tx(lead);
    let cap = core::create_academy(utf8(b"A"), utf8(b""), x"", s.ctx());
    let academy_id = cap.admin_academy_id();
    transfer::public_transfer(cap, lead);
    academy_id
}

fun new_budget(s: &mut Scenario, lead: address, config_id: ID, funded: u64): ID {
    s.next_tx(lead);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let budget_id = gas_budget::create_budget(&mut config, &cap, s.ctx());
    s.return_to_sender(cap);
    ts::return_shared(config);
    if (funded > 0) deposit(s, budget_id, funded);
    budget_id
}

fun deposit(s: &mut Scenario, budget_id: ID, amount: u64) {
    s.next_tx(FUNDER);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    budget.deposit(coin::mint_for_testing<SUI>(amount, s.ctx()), s.ctx());
    ts::return_shared(budget);
}

fun new_quest(s: &mut Scenario, lead: address, academy_id: ID): ID {
    s.next_tx(lead);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let quest_id = core::create_quest(
        &mut academy,
        &cap,
        test_handlers::identity(),
        vector[],
        vector[test_handlers::reward()],
        utf8(b""),
        x"",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    quest_id
}

fun world(s: &mut Scenario): (ID, ID, ID) {
    let config_id = publish(s);
    let academy_id = new_academy(s, LEAD);
    let budget_id = new_budget(s, LEAD, config_id, FUNDED);
    let quest_id = new_quest(s, LEAD, academy_id);
    (config_id, budget_id, quest_id)
}

fun next_sponsored(s: &mut Scenario, sender: address, sponsor: address) {
    let rgp = s.ctx().reference_gas_price();
    s.next_with_context(
        ts::ctx_builder_from_sender(sender).set_reference_gas_price(rgp).set_sponsor(sponsor),
    );
}

fun start_claim(quest: &mut Quest, player: address, game_id: u64): RewardTicket {
    let mut t = core::begin_claim(quest);
    test_handlers::bind(&mut t, tenant(), game_id, player);
    core::complete(t, quest)
}

fun finish_claim(mut rt: RewardTicket) {
    test_handlers::pay(&mut rt);
    core::finish(rt);
}

fun claim_with_charge(s: &mut Scenario, config_id: ID, budget_id: ID, quest_id: ID, player: address, game_id: u64, amount: u64) {
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let rt = start_claim(&mut quest, player, game_id);
    gas_budget::charge(&config, &mut budget, &rt, amount, s.ctx());
    finish_claim(rt);
    ts::return_shared(quest);
    ts::return_shared(budget);
    ts::return_shared(config);
}

fun budget_state(s: &mut Scenario, budget_id: ID): (u64, u64, u64, u64) {
    s.next_tx(FUNDER);
    let budget = s.take_shared_by_id<GasBudget>(budget_id);
    let (b, d, t, c) = (budget.balance(), budget.sponsor_due(), budget.charged_total(), budget.charges());
    ts::return_shared(budget);
    (b, d, t, c)
}

fun academy_of(s: &mut Scenario, budget_id: ID): ID {
    s.next_tx(FUNDER);
    let budget = s.take_shared_by_id<GasBudget>(budget_id);
    let academy_id = budget.academy_id();
    ts::return_shared(budget);
    academy_id
}

fun set_config(s: &mut Scenario, config_id: ID, sponsor: address) {
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let cap = s.take_from_sender<GasAdminCap>();
    config.set_sponsor(&cap, sponsor);
    s.return_to_sender(cap);
    ts::return_shared(config);
}

#[test]
fun init_creates_disabled_config_and_admin_cap() {
    let mut s = ts::begin(PUBLISHER);
    gas_budget::init_for_testing(s.ctx());
    s.next_tx(PUBLISHER);
    let config = s.take_shared<GasConfig>();
    assert!(config.sponsor() == @0x0);
    assert!(config.max_charge_per_claim() == DEFAULT_MAX);
    assert!(config.config_version() == gas_budget::package_version());
    assert!(gas_budget::max_charge_ceiling() == 50_000_000);
    ts::return_shared(config);
    assert!(s.has_most_recent_for_sender<GasAdminCap>());
    s.end();
}

#[test]
fun admin_sets_sponsor_and_max_charge() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let cap = s.take_from_sender<GasAdminCap>();
    config.set_max_charge(&cap, 50_000_000);
    config.set_max_charge(&cap, 1);
    config.set_sponsor(&cap, OTHER_SPONSOR);
    assert!(config.sponsor() == OTHER_SPONSOR);
    assert!(config.max_charge_per_claim() == 1);
    assert!(event::events_by_type<gas_budget::GasConfigChanged>().length() == 3);
    s.return_to_sender(cap);
    ts::return_shared(config);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::EMaxChargeOutOfRange)]
fun set_max_charge_above_ceiling_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let cap = s.take_from_sender<GasAdminCap>();
    config.set_max_charge(&cap, 50_000_001);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EMaxChargeOutOfRange)]
fun set_max_charge_zero_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let cap = s.take_from_sender<GasAdminCap>();
    config.set_max_charge(&cap, 0);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EWrongVersion)]
fun set_sponsor_on_old_config_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let cap = s.take_from_sender<GasAdminCap>();
    config.set_config_version_for_testing(0);
    config.set_sponsor(&cap, OTHER_SPONSOR);
    abort
}

#[test]
fun lead_creates_budget_at_derived_id() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    let academy_id = new_academy(&mut s, LEAD);
    s.next_tx(LEAD);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    assert!(!config.has_budget(academy_id));
    let expected = config.budget_id_for(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let budget_id = gas_budget::create_budget(&mut config, &cap, s.ctx());
    assert!(budget_id == expected);
    assert!(config.has_budget(academy_id));
    assert!(
        budget_id == sui::derived_object::derive_address(config_id, gas_budget::budget_key(academy_id)).to_id(),
    );
    assert!(event::events_by_type<gas_budget::BudgetCreated>().length() == 1);
    s.return_to_sender(cap);
    ts::return_shared(config);

    s.next_tx(LEAD);
    let budget = s.take_shared_by_id<GasBudget>(budget_id);
    assert!(budget.academy_id() == academy_id);
    assert!(budget.balance() == 0 && budget.sponsor_due() == 0);
    assert!(budget.charged_total() == 0 && budget.charges() == 0);
    assert!(!budget.is_paused());
    assert!(budget.budget_version() == gas_budget::package_version());
    ts::return_shared(budget);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::EBudgetExists)]
fun create_budget_twice_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    new_academy(&mut s, LEAD);
    new_budget(&mut s, LEAD, config_id, 0);
    new_budget(&mut s, LEAD, config_id, 0);
    abort
}

#[test]
fun anyone_deposits() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    new_academy(&mut s, LEAD);
    let budget_id = new_budget(&mut s, LEAD, config_id, 70);
    deposit(&mut s, budget_id, 30);
    let (balance, due, _, _) = budget_state(&mut s, budget_id);
    assert!(balance == 100 && due == 0);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::EZeroAmount)]
fun deposit_zero_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    new_academy(&mut s, LEAD);
    let budget_id = new_budget(&mut s, LEAD, config_id, 0);
    deposit(&mut s, budget_id, 0);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EWrongVersion)]
fun deposit_to_old_budget_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    new_academy(&mut s, LEAD);
    let budget_id = new_budget(&mut s, LEAD, config_id, 0);
    s.next_tx(FUNDER);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    budget.set_budget_version_for_testing(0);
    budget.deposit(coin::mint_for_testing<SUI>(1, s.ctx()), s.ctx());
    abort
}

#[test]
fun lead_withdraws_and_withdraws_all() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let part = budget.withdraw(&cap, 40_000_000, s.ctx());
    assert!(part.value() == 40_000_000);
    let rest = budget.withdraw_all(&cap, s.ctx());
    assert!(rest.value() == FUNDED - 40_000_000);
    assert!(budget.balance() == 0);
    assert!(event::events_by_type<gas_budget::BudgetWithdrawn>().length() == 2);
    part.burn_for_testing();
    rest.burn_for_testing();
    s.return_to_sender(cap);
    ts::return_shared(budget);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::ENotAcademyAdmin)]
fun withdraw_with_foreign_cap_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    new_academy(&mut s, OTHER_LEAD);
    s.next_tx(OTHER_LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let _c = budget.withdraw(&cap, 1, s.ctx());
    abort
}

#[test, expected_failure(abort_code = gas_budget::ENotAcademyAdmin)]
fun withdraw_all_with_foreign_cap_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    new_academy(&mut s, OTHER_LEAD);
    s.next_tx(OTHER_LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let _c = budget.withdraw_all(&cap, s.ctx());
    abort
}

#[test, expected_failure(abort_code = gas_budget::EWithdrawExceedsBalance)]
fun withdraw_more_than_balance_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let _c = budget.withdraw(&cap, FUNDED + 1, s.ctx());
    abort
}

#[test, expected_failure(abort_code = gas_budget::EZeroAmount)]
fun withdraw_zero_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let _c = budget.withdraw(&cap, 0, s.ctx());
    abort
}

#[test, expected_failure(abort_code = gas_budget::EZeroAmount)]
fun withdraw_all_of_empty_budget_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    new_academy(&mut s, LEAD);
    let budget_id = new_budget(&mut s, LEAD, config_id, 0);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let _c = budget.withdraw_all(&cap, s.ctx());
    abort
}

#[test]
fun withdraw_works_after_config_changes_and_pause() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, _) = world(&mut s);
    set_config(&mut s, config_id, OTHER_SPONSOR);
    set_config(&mut s, config_id, @0x0);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let admin = s.take_from_sender<GasAdminCap>();
    config.set_max_charge(&admin, 1);
    config.set_config_version_for_testing(0);
    s.return_to_sender(admin);
    ts::return_shared(config);

    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.set_paused(&cap, true);
    let c = budget.withdraw(&cap, FUNDED, s.ctx());
    assert!(c.value() == FUNDED);
    c.burn_for_testing();
    s.return_to_sender(cap);
    ts::return_shared(budget);
    s.end();
}

#[test]
fun withdraw_from_old_version_budget() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    budget.set_budget_version_for_testing(0);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.set_paused(&cap, true);
    let c = budget.withdraw_all(&cap, s.ctx());
    assert!(c.value() == FUNDED);
    c.burn_for_testing();
    s.return_to_sender(cap);
    ts::return_shared(budget);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::EWrongVersion)]
fun withdraw_from_newer_version_budget_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    budget.set_budget_version_for_testing(gas_budget::package_version() + 1);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let _c = budget.withdraw(&cap, 1, s.ctx());
    abort
}

#[test, expected_failure(abort_code = gas_budget::ENotAcademyAdmin)]
fun pause_with_foreign_cap_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    new_academy(&mut s, OTHER_LEAD);
    s.next_tx(OTHER_LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.set_paused(&cap, true);
    abort
}

#[test]
fun paused_budget_charges_nothing() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.set_paused(&cap, true);
    assert!(budget.is_paused());
    assert!(event::events_by_type<gas_budget::BudgetPaused>().length() == 1);
    s.return_to_sender(cap);
    ts::return_shared(budget);

    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1_000_000);
    let (balance, due, total, charges) = budget_state(&mut s, budget_id);
    assert!(balance == FUNDED && due == 0 && total == 0 && charges == 0);

    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.set_paused(&cap, false);
    s.return_to_sender(cap);
    ts::return_shared(budget);
    next_sponsored(&mut s, PLAYER_2, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER_2, 2, 1_000_000);
    let (balance, due, _, _) = budget_state(&mut s, budget_id);
    assert!(balance == FUNDED - 1_000_000 && due == 1_000_000);
    s.end();
}

#[test]
fun sponsored_claim_charges_budget() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 3_000_000);
    let charged = event::events_by_type<gas_budget::GasCharged>();
    assert!(charged.length() == 1);
    assert!(event::events_by_type<core::QuestCompleted>().length() == 1);
    assert!(
        charged[0] == gas_budget::new_gas_charged_for_testing(
            budget_id, academy_of(&mut s, budget_id), quest_id, PLAYER, 3_000_000, 3_000_000, FUNDED - 3_000_000,
        ),
    );
    let (balance, due, total, charges) = budget_state(&mut s, budget_id);
    assert!(balance == FUNDED - 3_000_000 && due == 3_000_000);
    assert!(total == 3_000_000 && charges == 1);

    next_sponsored(&mut s, PLAYER_2, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER_2, 2, DEFAULT_MAX);
    let (balance, due, total, charges) = budget_state(&mut s, budget_id);
    assert!(balance == FUNDED - 3_000_000 - DEFAULT_MAX && due == 3_000_000 + DEFAULT_MAX);
    assert!(total == 3_000_000 + DEFAULT_MAX && charges == 2);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::ENotSponsored)]
fun charge_without_sponsor_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    s.next_tx(PLAYER);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = gas_budget::ENotSponsored)]
fun charge_by_foreign_sponsor_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, OTHER_SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = gas_budget::ESponsorNotSet)]
fun charge_with_unset_sponsor_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    set_config(&mut s, config_id, @0x0);
    next_sponsored(&mut s, PLAYER, @0x0);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = gas_budget::ENotSponsored)]
fun charge_by_rotated_out_sponsor_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    set_config(&mut s, config_id, OTHER_SPONSOR);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EWrongAcademy)]
fun charge_with_foreign_academy_ticket_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, _) = world(&mut s);
    let other_academy = new_academy(&mut s, OTHER_LEAD);
    let other_quest = new_quest(&mut s, OTHER_LEAD, other_academy);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, other_quest, PLAYER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EChargeAboveCap)]
fun charge_above_cap_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, DEFAULT_MAX + 1);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EChargeAboveCap)]
fun charge_above_lowered_cap_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let admin = s.take_from_sender<GasAdminCap>();
    config.set_max_charge(&admin, 1_000);
    s.return_to_sender(admin);
    ts::return_shared(config);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1_001);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EZeroAmount)]
fun charge_zero_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 0);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EAlreadyChargedInTx)]
fun charge_twice_with_same_ticket_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let rt = start_claim(&mut quest, PLAYER, 1);
    gas_budget::charge(&config, &mut budget, &rt, 1_000, s.ctx());
    gas_budget::charge(&config, &mut budget, &rt, 1_000, s.ctx());
    abort
}

#[test, expected_failure(abort_code = gas_budget::EAlreadyChargedInTx)]
fun charge_twice_with_two_claims_in_one_tx_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let rt1 = start_claim(&mut quest, PLAYER, 1);
    gas_budget::charge(&config, &mut budget, &rt1, 1_000, s.ctx());
    finish_claim(rt1);
    let rt2 = start_claim(&mut quest, PLAYER_2, 2);
    gas_budget::charge(&config, &mut budget, &rt2, 1_000, s.ctx());
    abort
}

#[test]
fun charge_saturates_at_balance() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    let academy_id = new_academy(&mut s, LEAD);
    let budget_id = new_budget(&mut s, LEAD, config_id, 500);
    let quest_id = new_quest(&mut s, LEAD, academy_id);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 2_000);
    let ev = event::events_by_type<gas_budget::GasCharged>();
    assert!(ev[0] == gas_budget::new_gas_charged_for_testing(budget_id, academy_id, quest_id, PLAYER, 2_000, 500, 0));
    let (balance, due, total, charges) = budget_state(&mut s, budget_id);
    assert!(balance == 0 && due == 500 && total == 500 && charges == 1);

    next_sponsored(&mut s, PLAYER_2, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER_2, 2, 2_000);
    let (balance, due, total, charges) = budget_state(&mut s, budget_id);
    assert!(balance == 0 && due == 500 && total == 500 && charges == 1);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::EWrongVersion)]
fun charge_old_budget_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    budget.set_budget_version_for_testing(0);
    ts::return_shared(budget);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EWrongVersion)]
fun charge_old_config_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    config.set_config_version_for_testing(0);
    ts::return_shared(config);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 1);
    abort
}

#[test]
fun withdraw_does_not_touch_sponsor_due() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, LEAD, SPONSOR);
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let rt = start_claim(&mut quest, LEAD, 1);
    gas_budget::charge(&config, &mut budget, &rt, 7_000_000, s.ctx());
    let c = budget.withdraw_all(&cap, s.ctx());
    finish_claim(rt);
    assert!(c.value() == FUNDED - 7_000_000);
    assert!(budget.sponsor_due() == 7_000_000 && budget.balance() == 0);
    c.burn_for_testing();
    s.return_to_sender(cap);
    ts::return_shared(quest);
    ts::return_shared(budget);
    ts::return_shared(config);
    s.end();
}

#[test]
fun collect_sends_exactly_due_to_config_sponsor() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 4_000_000);
    next_sponsored(&mut s, PLAYER_2, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER_2, 2, 5_000_000);

    s.next_tx(PLAYER);
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    gas_budget::collect(&config, &mut budget, s.ctx());
    assert!(budget.sponsor_due() == 0);
    assert!(budget.balance() == FUNDED - 9_000_000);
    assert!(event::events_by_type<gas_budget::DueCollected>().length() == 1);
    ts::return_shared(budget);
    ts::return_shared(config);

    s.next_tx(PLAYER);
    let coin = s.take_from_address<Coin<SUI>>(SPONSOR);
    assert!(coin.value() == 9_000_000);
    assert!(!ts::has_most_recent_for_address<Coin<SUI>>(PLAYER));
    ts::return_to_address(SPONSOR, coin);
    s.end();
}

#[test]
fun collect_after_rotation_goes_to_new_sponsor() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 4_000_000);
    set_config(&mut s, config_id, OTHER_SPONSOR);
    s.next_tx(SPONSOR);
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    gas_budget::collect(&config, &mut budget, s.ctx());
    ts::return_shared(budget);
    ts::return_shared(config);
    s.next_tx(SPONSOR);
    let coin = s.take_from_address<Coin<SUI>>(OTHER_SPONSOR);
    assert!(coin.value() == 4_000_000);
    assert!(!ts::has_most_recent_for_address<Coin<SUI>>(SPONSOR));
    ts::return_to_address(OTHER_SPONSOR, coin);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::ENothingToCollect)]
fun collect_nothing_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, _) = world(&mut s);
    s.next_tx(PLAYER);
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    gas_budget::collect(&config, &mut budget, s.ctx());
    abort
}

#[test, expected_failure(abort_code = gas_budget::ESponsorNotSet)]
fun collect_with_unset_sponsor_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, quest_id) = world(&mut s);
    next_sponsored(&mut s, PLAYER, SPONSOR);
    claim_with_charge(&mut s, config_id, budget_id, quest_id, PLAYER, 1, 4_000_000);
    set_config(&mut s, config_id, @0x0);
    s.next_tx(PLAYER);
    let config = s.take_shared_by_id<GasConfig>(config_id);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    gas_budget::collect(&config, &mut budget, s.ctx());
    abort
}

#[test]
fun migrate_budget_and_config() {
    let mut s = ts::begin(PUBLISHER);
    let (config_id, budget_id, _) = world(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let admin = s.take_from_sender<GasAdminCap>();
    config.set_config_version_for_testing(0);
    config.migrate_config(&admin);
    assert!(config.config_version() == gas_budget::package_version());
    s.return_to_sender(admin);
    ts::return_shared(config);

    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.set_budget_version_for_testing(0);
    budget.migrate_budget(&cap);
    assert!(budget.budget_version() == gas_budget::package_version());
    assert!(budget.balance() == FUNDED);
    s.return_to_sender(cap);
    ts::return_shared(budget);
    s.end();
}

#[test, expected_failure(abort_code = gas_budget::EAlreadyMigrated)]
fun migrate_current_budget_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    s.next_tx(LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.migrate_budget(&cap);
    abort
}

#[test, expected_failure(abort_code = gas_budget::ENotAcademyAdmin)]
fun migrate_budget_with_foreign_cap_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let (_, budget_id, _) = world(&mut s);
    new_academy(&mut s, OTHER_LEAD);
    s.next_tx(OTHER_LEAD);
    let mut budget = s.take_shared_by_id<GasBudget>(budget_id);
    budget.set_budget_version_for_testing(0);
    let cap = s.take_from_sender<AcademyAdminCap>();
    budget.migrate_budget(&cap);
    abort
}

#[test, expected_failure(abort_code = gas_budget::EAlreadyMigrated)]
fun migrate_current_config_aborts() {
    let mut s = ts::begin(PUBLISHER);
    let config_id = publish(&mut s);
    s.next_tx(PUBLISHER);
    let mut config = s.take_shared_by_id<GasConfig>(config_id);
    let admin = s.take_from_sender<GasAdminCap>();
    config.migrate_config(&admin);
    abort
}
