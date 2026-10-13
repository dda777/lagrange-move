module academy_core::core;

use std::{bcs, internal::Permit, string::String, type_name::{Self, TypeName}};
use sui::{derived_object, event};

const VERSION: u64 = 1;

#[error(code = 1)]
const EWrongVersion: vector<u8> = b"Object version does not match the package version";
#[error(code = 2)]
const ENotAcademyAdmin: vector<u8> = b"AcademyAdminCap belongs to another academy";
#[error(code = 3)]
const EQuestInactive: vector<u8> = b"Quest is not active";
#[error(code = 4)]
const EIdentityAlreadySet: vector<u8> = b"Player identity is already bound to the ticket";
#[error(code = 5)]
const ENoIdentity: vector<u8> = b"Player identity is not bound to the ticket";
#[error(code = 6)]
const EWrongRequirement: vector<u8> = b"Next requirement belongs to another handler type";
#[error(code = 7)]
const ENoPendingRequirement: vector<u8> = b"No pending requirement left";
#[error(code = 8)]
const EChecksPending: vector<u8> = b"Not all quest checks are done";
#[error(code = 9)]
const EPrerequisitesPending: vector<u8> = b"Not all quest prerequisites are proven";
#[error(code = 10)]
const ERewardsPending: vector<u8> = b"Not all quest rewards are paid";
#[error(code = 11)]
const EWrongQuest: vector<u8> = b"Ticket belongs to another quest";
#[error(code = 12)]
const EAlreadyClaimedByPlayer: vector<u8> = b"This character has already claimed the quest";
#[error(code = 13)]
const EAlreadyClaimedByWallet: vector<u8> = b"This wallet has already claimed the quest";
#[error(code = 14)]
const EEvidenceUsed: vector<u8> = b"This evidence has already been used in the quest";
#[error(code = 15)]
const EWrongIdentity: vector<u8> = b"Identity adapter is not the one configured in the quest";
#[error(code = 16)]
const EHandlerMismatch: vector<u8> = b"Caller is not the handler of the current requirement";
#[error(code = 17)]
const ERulesFrozen: vector<u8> = b"Quest rules cannot change after the first claim";
#[error(code = 18)]
const EWrongAcademy: vector<u8> = b"Prerequisite quest belongs to another academy";
#[error(code = 19)]
const ENotPrerequisite: vector<u8> = b"Quest is not a pending prerequisite";
#[error(code = 20)]
const EPrerequisiteNotCompleted: vector<u8> = b"Character has not completed the prerequisite quest";
#[error(code = 21)]
const EPrerequisiteDuplicate: vector<u8> = b"Prerequisite is already added";
#[error(code = 22)]
const EPrerequisiteCycle: vector<u8> = b"Prerequisite quest itself requires this quest";
#[error(code = 23)]
const ERulesChanged: vector<u8> = b"Quest rules changed during the claim";
#[error(code = 26)]
const EAlreadyMigrated: vector<u8> = b"Object is already at the current package version";

public struct Academy has key {
    id: UID,
    version: u64,
    name: String,
    content_uri: String,
    content_hash: vector<u8>,
    quests: vector<ID>,
}

public struct AcademyAdminCap has key, store {
    id: UID,
    academy_id: ID,
}

public struct Requirement has copy, drop, store {
    type_name: TypeName,
    data: vector<u8>,
}

public struct Quest has key {
    id: UID,
    version: u64,
    academy_id: ID,
    identity: Requirement,
    checks: vector<Requirement>,
    rewards: vector<Requirement>,
    prerequisites: vector<ID>,
    active: bool,
    claims: u64,
    rules_revision: u64,
    content_uri: String,
    content_hash: vector<u8>,
}

public struct PlayerKey has copy, drop, store { tenant: String, game_id: u64 }

public struct WalletKey has copy, drop, store { addr: address }

public struct EvidenceKey has copy, drop, store { object_id: ID }

public struct ClaimMarker has key { id: UID }

public struct ClaimTicket {
    quest_id: ID,
    academy_id: ID,
    identity: TypeName,
    player: Option<PlayerKey>,
    recipient: Option<address>,
    pending_checks: vector<Requirement>,
    current_check: Option<TypeName>,
    pending_prerequisites: vector<ID>,
    evidence: vector<ID>,
    rules_revision: u64,
}

public struct RewardTicket {
    quest_id: ID,
    academy_id: ID,
    player: PlayerKey,
    recipient: address,
    pending_rewards: vector<Requirement>,
    current_reward: Option<TypeName>,
}

public struct AcademyCreated has copy, drop { academy_id: ID, admin_cap_id: ID, name: String }

public struct QuestCreated has copy, drop { quest_id: ID, academy_id: ID }

public struct QuestUpdated has copy, drop { quest_id: ID, academy_id: ID, field: String }

public struct AcademyUpdated has copy, drop { academy_id: ID }

public struct QuestCompleted has copy, drop {
    quest_id: ID,
    tenant: String,
    game_id: u64,
    wallet: address,
}

public struct RewardPaid has copy, drop { quest_id: ID, reward_type: TypeName, amount: u64 }

public fun create_academy(
    name: String,
    content_uri: String,
    content_hash: vector<u8>,
    ctx: &mut TxContext,
): AcademyAdminCap {
    let academy = Academy {
        id: object::new(ctx),
        version: VERSION,
        name,
        content_uri,
        content_hash,
        quests: vector[],
    };
    let academy_id = object::id(&academy);
    let cap = AcademyAdminCap { id: object::new(ctx), academy_id };
    event::emit(AcademyCreated { academy_id, admin_cap_id: object::id(&cap), name });
    transfer::share_object(academy);
    cap
}

public fun create_quest(
    academy: &mut Academy,
    cap: &AcademyAdminCap,
    identity: Requirement,
    checks: vector<Requirement>,
    rewards: vector<Requirement>,
    content_uri: String,
    content_hash: vector<u8>,
    ctx: &mut TxContext,
): ID {
    assert!(academy.version == VERSION, EWrongVersion);
    assert!(cap.academy_id == object::id(academy), ENotAcademyAdmin);
    let quest = Quest {
        id: object::new(ctx),
        version: VERSION,
        academy_id: cap.academy_id,
        identity,
        checks,
        rewards,
        prerequisites: vector[],
        active: true,
        claims: 0,
        rules_revision: 0,
        content_uri,
        content_hash,
    };
    let quest_id = object::id(&quest);
    academy.quests.push_back(quest_id);
    event::emit(QuestCreated { quest_id, academy_id: cap.academy_id });
    transfer::share_object(quest);
    quest_id
}

public fun set_academy_content(
    academy: &mut Academy,
    cap: &AcademyAdminCap,
    content_uri: String,
    content_hash: vector<u8>,
) {
    assert!(academy.version == VERSION, EWrongVersion);
    assert!(cap.academy_id == object::id(academy), ENotAcademyAdmin);
    academy.content_uri = content_uri;
    academy.content_hash = content_hash;
    event::emit(AcademyUpdated { academy_id: object::id(academy) });
}

public fun requirement<T: drop>(cfg: T): Requirement {
    Requirement { type_name: type_name::with_original_ids<T>(), data: bcs::to_bytes(&cfg) }
}

public fun set_active(quest: &mut Quest, cap: &AcademyAdminCap, active: bool) {
    assert_admin(quest, cap);
    quest.active = active;
    emit_updated(quest, b"active");
}

public fun set_content(
    quest: &mut Quest,
    cap: &AcademyAdminCap,
    content_uri: String,
    content_hash: vector<u8>,
) {
    assert_admin(quest, cap);
    quest.content_uri = content_uri;
    quest.content_hash = content_hash;
    emit_updated(quest, b"content");
}

public fun set_identity(quest: &mut Quest, cap: &AcademyAdminCap, identity: Requirement) {
    assert_rules_editable(quest, cap);
    quest.identity = identity;
    rules_changed(quest, b"identity");
}

public fun set_checks(quest: &mut Quest, cap: &AcademyAdminCap, checks: vector<Requirement>) {
    assert_rules_editable(quest, cap);
    quest.checks = checks;
    rules_changed(quest, b"checks");
}

public fun set_rewards(quest: &mut Quest, cap: &AcademyAdminCap, rewards: vector<Requirement>) {
    assert_rules_editable(quest, cap);
    quest.rewards = rewards;
    rules_changed(quest, b"rewards");
}

public fun add_prerequisite(quest: &mut Quest, cap: &AcademyAdminCap, prereq: &Quest) {
    assert_rules_editable(quest, cap);
    assert!(prereq.version == VERSION, EWrongVersion);
    assert!(prereq.academy_id == quest.academy_id, EWrongAcademy);
    let prereq_id = object::id(prereq);
    assert!(!quest.prerequisites.contains(&prereq_id), EPrerequisiteDuplicate);
    assert!(!prereq.prerequisites.contains(&object::id(quest)), EPrerequisiteCycle);
    quest.prerequisites.push_back(prereq_id);
    rules_changed(quest, b"prerequisites");
}

public fun remove_prerequisite(quest: &mut Quest, cap: &AcademyAdminCap, prereq_id: ID) {
    assert_rules_editable(quest, cap);
    let (found, i) = quest.prerequisites.index_of(&prereq_id);
    assert!(found, ENotPrerequisite);
    quest.prerequisites.remove(i);
    rules_changed(quest, b"prerequisites");
}

public fun migrate_academy(academy: &mut Academy, cap: &AcademyAdminCap) {
    assert!(cap.academy_id == object::id(academy), ENotAcademyAdmin);
    assert!(academy.version < VERSION, EAlreadyMigrated);
    academy.version = VERSION;
}

public fun migrate_quest(quest: &mut Quest, cap: &AcademyAdminCap) {
    assert!(cap.academy_id == quest.academy_id, ENotAcademyAdmin);
    assert!(quest.version < VERSION, EAlreadyMigrated);
    quest.version = VERSION;
}

public fun begin_claim(quest: &Quest): ClaimTicket {
    assert!(quest.version == VERSION, EWrongVersion);
    assert!(quest.active, EQuestInactive);
    let mut pending_checks = quest.checks;
    pending_checks.reverse();
    ClaimTicket {
        quest_id: object::id(quest),
        academy_id: quest.academy_id,
        identity: quest.identity.type_name,
        player: option::none(),
        recipient: option::none(),
        pending_checks,
        current_check: option::none(),
        pending_prerequisites: quest.prerequisites,
        evidence: vector[],
        rules_revision: quest.rules_revision,
    }
}

public fun bind_player<T>(
    t: &mut ClaimTicket,
    _: Permit<T>,
    tenant: String,
    game_id: u64,
    recipient: address,
) {
    assert!(type_name::with_original_ids<T>() == t.identity, EWrongIdentity);
    assert!(t.player.is_none(), EIdentityAlreadySet);
    t.player.fill(PlayerKey { tenant, game_id });
    t.recipient.fill(recipient);
}

public fun prove_prereq(t: &mut ClaimTicket, prereq: &Quest) {
    assert!(prereq.version == VERSION, EWrongVersion);
    assert!(prereq.academy_id == t.academy_id, EWrongAcademy);
    assert!(t.player.is_some(), ENoIdentity);
    let (found, i) = t.pending_prerequisites.index_of(&object::id(prereq));
    assert!(found, ENotPrerequisite);
    let wallet = WalletKey { addr: *t.recipient.borrow() };
    assert!(
        derived_object::exists(&prereq.id, *t.player.borrow())
            || derived_object::exists(&prereq.id, wallet),
        EPrerequisiteNotCompleted,
    );
    t.pending_prerequisites.swap_remove(i);
}

public fun take_check<T>(t: &mut ClaimTicket, _: Permit<T>): vector<u8> {
    let data = take_next<T>(&mut t.pending_checks);
    t.current_check = option::some(type_name::with_original_ids<T>());
    data
}

public fun add_evidence<T>(t: &mut ClaimTicket, _: Permit<T>, object_id: ID) {
    assert!(t.current_check == option::some(type_name::with_original_ids<T>()), EHandlerMismatch);
    t.evidence.push_back(object_id);
}

public fun complete(t: ClaimTicket, quest: &mut Quest): RewardTicket {
    assert!(quest.version == VERSION, EWrongVersion);
    let ClaimTicket {
        quest_id,
        academy_id,
        identity: _,
        player,
        recipient,
        pending_checks,
        current_check: _,
        pending_prerequisites,
        evidence,
        rules_revision,
    } = t;
    assert!(quest_id == object::id(quest), EWrongQuest);
    assert!(quest.active, EQuestInactive);
    assert!(rules_revision == quest.rules_revision, ERulesChanged);
    assert!(pending_checks.is_empty(), EChecksPending);
    assert!(pending_prerequisites.is_empty(), EPrerequisitesPending);
    assert!(player.is_some(), ENoIdentity);
    let player = player.destroy_some();
    let recipient = recipient.destroy_some();

    assert!(!derived_object::exists(&quest.id, player), EAlreadyClaimedByPlayer);
    new_marker(&mut quest.id, player);
    let wallet = WalletKey { addr: recipient };
    assert!(!derived_object::exists(&quest.id, wallet), EAlreadyClaimedByWallet);
    new_marker(&mut quest.id, wallet);
    evidence.do!(|object_id| {
        let key = EvidenceKey { object_id };
        assert!(!derived_object::exists(&quest.id, key), EEvidenceUsed);
        new_marker(&mut quest.id, key);
    });
    quest.claims = quest.claims + 1;

    event::emit(QuestCompleted {
        quest_id,
        tenant: player.tenant,
        game_id: player.game_id,
        wallet: recipient,
    });
    let mut pending_rewards = quest.rewards;
    pending_rewards.reverse();
    RewardTicket {
        quest_id,
        academy_id,
        player,
        recipient,
        pending_rewards,
        current_reward: option::none(),
    }
}

public fun take_reward<T>(rt: &mut RewardTicket, _: Permit<T>): (ID, address, vector<u8>) {
    let data = take_next<T>(&mut rt.pending_rewards);
    rt.current_reward = option::some(type_name::with_original_ids<T>());
    (rt.quest_id, rt.recipient, data)
}

public fun peek_reward<T>(rt: &RewardTicket): vector<u8> {
    assert!(!rt.pending_rewards.is_empty(), ENoPendingRequirement);
    let next = &rt.pending_rewards[rt.pending_rewards.length() - 1];
    assert!(next.type_name == type_name::with_original_ids<T>(), EWrongRequirement);
    next.data
}

public fun skip_optional_reward<T>(rt: &mut RewardTicket, _: Permit<T>): vector<u8> {
    let data = take_next<T>(&mut rt.pending_rewards);
    rt.current_reward = option::none();
    data
}

public fun record_payment<T>(rt: &RewardTicket, _: Permit<T>, amount: u64) {
    assert!(rt.current_reward == option::some(type_name::with_original_ids<T>()), EHandlerMismatch);
    event::emit(RewardPaid {
        quest_id: rt.quest_id,
        reward_type: type_name::with_original_ids<T>(),
        amount,
    });
}

public fun finish(rt: RewardTicket) {
    let RewardTicket { pending_rewards, .. } = rt;
    assert!(pending_rewards.is_empty(), ERewardsPending);
}

public fun admin_academy_id(cap: &AcademyAdminCap): ID { cap.academy_id }

public fun package_version(): u64 { VERSION }

public fun academy_version(academy: &Academy): u64 { academy.version }

public fun quest_version(quest: &Quest): u64 { quest.version }

public fun name(academy: &Academy): String { academy.name }

public fun academy_content_uri(academy: &Academy): String { academy.content_uri }

public fun academy_content_hash(academy: &Academy): vector<u8> { academy.content_hash }

public fun quests(academy: &Academy): vector<ID> { academy.quests }

public fun academy_id(quest: &Quest): ID { quest.academy_id }

public fun identity(quest: &Quest): Requirement { quest.identity }

public fun checks(quest: &Quest): vector<Requirement> { quest.checks }

public fun rewards(quest: &Quest): vector<Requirement> { quest.rewards }

public fun prerequisites(quest: &Quest): vector<ID> { quest.prerequisites }

public fun is_active(quest: &Quest): bool { quest.active }

public fun claims(quest: &Quest): u64 { quest.claims }

public fun rules_revision(quest: &Quest): u64 { quest.rules_revision }

public fun quest_content_uri(quest: &Quest): String { quest.content_uri }

public fun quest_content_hash(quest: &Quest): vector<u8> { quest.content_hash }

public fun requirement_type(r: &Requirement): TypeName { r.type_name }

public fun requirement_data(r: &Requirement): vector<u8> { r.data }

public fun has_player_claimed(quest: &Quest, tenant: String, game_id: u64): bool {
    derived_object::exists(&quest.id, PlayerKey { tenant, game_id })
}

public fun has_wallet_claimed(quest: &Quest, addr: address): bool {
    derived_object::exists(&quest.id, WalletKey { addr })
}

public fun is_evidence_used(quest: &Quest, object_id: ID): bool {
    derived_object::exists(&quest.id, EvidenceKey { object_id })
}

public fun claim_quest_id(t: &ClaimTicket): ID { t.quest_id }

public fun claim_academy_id(t: &ClaimTicket): ID { t.academy_id }

public fun is_bound(t: &ClaimTicket): bool { t.player.is_some() }

public fun claim_tenant(t: &ClaimTicket): String {
    assert!(t.player.is_some(), ENoIdentity);
    t.player.borrow().tenant
}

public fun claim_game_id(t: &ClaimTicket): u64 {
    assert!(t.player.is_some(), ENoIdentity);
    t.player.borrow().game_id
}

public fun claim_recipient(t: &ClaimTicket): address {
    assert!(t.recipient.is_some(), ENoIdentity);
    *t.recipient.borrow()
}

public fun reward_quest_id(rt: &RewardTicket): ID { rt.quest_id }

public fun reward_academy_id(rt: &RewardTicket): ID { rt.academy_id }

public fun reward_tenant(rt: &RewardTicket): String { rt.player.tenant }

public fun reward_game_id(rt: &RewardTicket): u64 { rt.player.game_id }

public fun reward_recipient(rt: &RewardTicket): address { rt.recipient }

public fun pending_prerequisites(t: &ClaimTicket): vector<ID> { t.pending_prerequisites }

fun assert_admin(quest: &Quest, cap: &AcademyAdminCap) {
    assert!(quest.version == VERSION, EWrongVersion);
    assert!(cap.academy_id == quest.academy_id, ENotAcademyAdmin);
}

fun assert_rules_editable(quest: &Quest, cap: &AcademyAdminCap) {
    assert_admin(quest, cap);
    assert!(quest.claims == 0, ERulesFrozen);
}

fun rules_changed(quest: &mut Quest, field: vector<u8>) {
    quest.rules_revision = quest.rules_revision + 1;
    emit_updated(quest, field);
}

fun emit_updated(quest: &Quest, field: vector<u8>) {
    event::emit(QuestUpdated {
        quest_id: object::id(quest),
        academy_id: quest.academy_id,
        field: field.to_string(),
    });
}

fun take_next<T>(pending: &mut vector<Requirement>): vector<u8> {
    assert!(!pending.is_empty(), ENoPendingRequirement);
    let Requirement { type_name, data } = pending.pop_back();
    assert!(type_name == type_name::with_original_ids<T>(), EWrongRequirement);
    data
}

fun new_marker<K: copy + drop + store>(quest_uid: &mut UID, key: K) {
    transfer::freeze_object(ClaimMarker { id: derived_object::claim(quest_uid, key) });
}

#[test_only]
public fun set_academy_version_for_testing(academy: &mut Academy, version: u64) {
    academy.version = version;
}

#[test_only]
public fun set_quest_version_for_testing(quest: &mut Quest, version: u64) {
    quest.version = version;
}

#[test_only]
public fun set_active_for_testing(quest: &mut Quest, active: bool) {
    quest.active = active;
}
