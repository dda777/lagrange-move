module academy_world_v0::world_v0;

use academy_core::core::{Self, ClaimTicket, Requirement};
use std::internal;
use sui::bcs;
use world::{
    access::{Self, OwnerCap},
    assembly::Assembly,
    character::Character,
    gate::Gate,
    killmail::Killmail,
    location::{Self, LocationRegistry},
    network_node::NetworkNode,
    storage_unit::StorageUnit,
    turret::Turret
};

#[error(code = 100)]
const ENotCharacterOwner: vector<u8> = b"Sender is not the owner of the character";
#[error(code = 101)]
const ENotAuthorized: vector<u8> = b"OwnerCap does not belong to the network node";
#[error(code = 102)]
const ENodeOffline: vector<u8> = b"Network node is offline";
#[error(code = 103)]
const EWrongAssemblyKind: vector<u8> = b"Quest requires an assembly of another kind";
#[error(code = 104)]
const EAssemblyNotAuthorized: vector<u8> = b"OwnerCap does not belong to the assembly";
#[error(code = 105)]
const EAssemblyOffline: vector<u8> = b"Assembly is offline";
#[error(code = 106)]
const EInvalidAssemblyKind: vector<u8> = b"Unknown assembly kind";
#[error(code = 107)]
const ENotKiller: vector<u8> = b"Killmail killer is not the player";
#[error(code = 108)]
const EKillTooOld: vector<u8> = b"Kill happened before the quest window";
#[error(code = 109)]
const ECharacterMismatch: vector<u8> = b"Character is not the player bound to the claim";
#[error(code = 110)]
const EWrongTribe: vector<u8> = b"Character is not in the required tribe";
#[error(code = 111)]
const EInvalidTribe: vector<u8> = b"Tribe id must not be zero";
#[error(code = 112)]
const ESelfKill: vector<u8> = b"Killmail killer and victim are the same";
#[error(code = 113)]
const EWrongAssemblyType: vector<u8> = b"Assembly type is not accepted by the quest";
#[error(code = 114)]
const EInvalidAssemblyTypes: vector<u8> = b"Assembly type list must have 1 to 16 non-zero ids";
#[error(code = 115)]
const EDappUrlMismatch: vector<u8> = b"Storage unit dApp URL does not point to the required host";
#[error(code = 116)]
const ELocationNotPublic: vector<u8> = b"Storage unit location is not published";
#[error(code = 117)]
const ENotInPlayerTribe: vector<u8> = b"Character is not in a player tribe";
#[error(code = 118)]
const EInvalidHost: vector<u8> = b"Host must be 1 to 253 bytes of a-z, 0-9, dot or hyphen";

const KIND_STORAGE_UNIT: u8 = 1;
const KIND_GATE: u8 = 2;
const KIND_TURRET: u8 = 3;
const HTTPS_SCHEME: vector<u8> = b"https://";
const PLAYER_TRIBE_MIN_ID: u32 = 98_000_000;
const MAX_ASSEMBLY_TYPES: u64 = 16;
const MAX_HOST_LEN: u64 = 253;

public struct Identity() has drop;

public struct NodeOnline has drop {}

public struct AssemblyOnline has drop { kind: u8 }

public struct Kill has drop { min_ts_sec: u64 }

public struct InTribe has drop { tribe_id: u32 }

public struct InPlayerTribe has drop {}

public struct AssemblyTypeOnline has drop { type_ids: vector<u64> }

public struct StorageDappLink has drop { host: vector<u8> }

public fun kind_storage_unit(): u8 { KIND_STORAGE_UNIT }

public fun kind_gate(): u8 { KIND_GATE }

public fun kind_turret(): u8 { KIND_TURRET }

public fun player_tribe_min_id(): u32 { PLAYER_TRIBE_MIN_ID }

public fun identity(): Requirement {
    core::requirement(Identity())
}

public fun node_online(): Requirement {
    core::requirement(NodeOnline {})
}

public fun assembly_online(kind: u8): Requirement {
    assert!(kind == KIND_STORAGE_UNIT || kind == KIND_GATE || kind == KIND_TURRET, EInvalidAssemblyKind);
    core::requirement(AssemblyOnline { kind })
}

public fun kill(min_ts_sec: u64): Requirement {
    core::requirement(Kill { min_ts_sec })
}

public fun in_tribe(tribe_id: u32): Requirement {
    assert!(tribe_id != 0, EInvalidTribe);
    core::requirement(InTribe { tribe_id })
}

public fun in_player_tribe(): Requirement {
    core::requirement(InPlayerTribe {})
}

public fun assembly_type_online(type_ids: vector<u64>): Requirement {
    let n = type_ids.length();
    assert!(n > 0 && n <= MAX_ASSEMBLY_TYPES && !type_ids.contains(&0), EInvalidAssemblyTypes);
    core::requirement(AssemblyTypeOnline { type_ids })
}

public fun storage_dapp_link(host: vector<u8>): Requirement {
    assert!(is_valid_host(&host), EInvalidHost);
    core::requirement(StorageDappLink { host })
}

public fun bind(t: &mut ClaimTicket, character: &Character, ctx: &mut TxContext) {
    let owner = character.character_address();
    assert!(owner == ctx.sender(), ENotCharacterOwner);
    let key = character.key();
    t.bind_player(internal::permit<Identity>(), key.tenant(), key.item_id(), owner);
}

public fun check_node_online(t: &mut ClaimTicket, nwn: &NetworkNode, cap: &OwnerCap<NetworkNode>) {
    let _ = t.take_check(internal::permit<NodeOnline>());
    assert!(access::is_authorized(cap, nwn.id()), ENotAuthorized);
    assert!(nwn.is_network_node_online(), ENodeOffline);
    t.add_evidence(internal::permit<NodeOnline>(), nwn.id());
}

public fun check_storage_unit_online(
    t: &mut ClaimTicket,
    su: &StorageUnit,
    cap: &OwnerCap<StorageUnit>,
) {
    check_assembly(
        t,
        KIND_STORAGE_UNIT,
        access::is_authorized(cap, su.id()),
        su.status().is_online(),
        su.id(),
    );
}

public fun check_gate_online(t: &mut ClaimTicket, gate: &Gate, cap: &OwnerCap<Gate>) {
    check_assembly(t, KIND_GATE, access::is_authorized(cap, gate.id()), gate.is_online(), gate.id());
}

public fun check_turret_online(t: &mut ClaimTicket, turret: &Turret, cap: &OwnerCap<Turret>) {
    check_assembly(
        t,
        KIND_TURRET,
        access::is_authorized(cap, turret.id()),
        turret.is_online(),
        turret.id(),
    );
}

public fun check_kill(t: &mut ClaimTicket, killmail: &Killmail) {
    let min_ts_sec = bcs::new(t.take_check(internal::permit<Kill>())).peel_u64();
    let killer = killmail.killer_id();
    assert!(
        killer.tenant() == t.claim_tenant() && killer.item_id() == t.claim_game_id(),
        ENotKiller,
    );
    assert!(killer != killmail.victim_id(), ESelfKill);
    assert!(killmail.kill_timestamp() >= min_ts_sec, EKillTooOld);
    t.add_evidence(internal::permit<Kill>(), killmail.id());
}

public fun check_in_tribe(t: &mut ClaimTicket, character: &Character) {
    let tribe_id = bcs::new(t.take_check(internal::permit<InTribe>())).peel_u32();
    let key = character.key();
    assert!(key.tenant() == t.claim_tenant() && key.item_id() == t.claim_game_id(), ECharacterMismatch);
    assert!(character.tribe() == tribe_id, EWrongTribe);
}

public fun check_in_player_tribe(t: &mut ClaimTicket, character: &Character) {
    let _ = t.take_check(internal::permit<InPlayerTribe>());
    let key = character.key();
    assert!(key.tenant() == t.claim_tenant() && key.item_id() == t.claim_game_id(), ECharacterMismatch);
    assert!(character.tribe() >= PLAYER_TRIBE_MIN_ID, ENotInPlayerTribe);
}

public fun check_assembly_type_online(t: &mut ClaimTicket, assembly: &Assembly, cap: &OwnerCap<Assembly>) {
    let type_ids = bcs::new(t.take_check(internal::permit<AssemblyTypeOnline>())).peel_vec_u64();
    assert!(access::is_authorized(cap, assembly.id()), EAssemblyNotAuthorized);
    assert!(type_ids.contains(&assembly_type_id(assembly)), EWrongAssemblyType);
    assert!(assembly.status().is_online(), EAssemblyOffline);
    t.add_evidence(internal::permit<AssemblyTypeOnline>(), assembly.id());
}

public fun check_storage_dapp_link(
    t: &mut ClaimTicket,
    su: &StorageUnit,
    cap: &OwnerCap<StorageUnit>,
    registry: &LocationRegistry,
) {
    let host = bcs::new(t.take_check(internal::permit<StorageDappLink>())).peel_vec_u8();
    assert!(access::is_authorized(cap, su.id()), EAssemblyNotAuthorized);
    assert!(url_host(&storage_unit_url(su)) == host, EDappUrlMismatch);
    assert!(location::get_location(registry, su.id()).is_some(), ELocationNotPublic);
    t.add_evidence(internal::permit<StorageDappLink>(), su.id());
}

fun check_assembly(t: &mut ClaimTicket, kind: u8, authorized: bool, online: bool, assembly_id: ID) {
    let expected = bcs::new(t.take_check(internal::permit<AssemblyOnline>())).peel_u8();
    assert!(expected == kind, EWrongAssemblyKind);
    assert!(authorized, EAssemblyNotAuthorized);
    assert!(online, EAssemblyOffline);
    t.add_evidence(internal::permit<AssemblyOnline>(), assembly_id);
}

fun peel_type_id(b: &mut bcs::BCS): u64 {
    let _ = b.peel_address();
    let _ = b.peel_u64();
    let _ = b.peel_vec_u8();
    let _ = b.peel_address();
    b.peel_u64()
}

fun assembly_type_id(assembly: &Assembly): u64 {
    let mut b = bcs::new(std::bcs::to_bytes(assembly));
    peel_type_id(&mut b)
}

fun storage_unit_url(su: &StorageUnit): vector<u8> {
    let mut b = bcs::new(std::bcs::to_bytes(su));
    let _ = peel_type_id(&mut b);
    let _ = b.peel_enum_tag();
    let _ = b.peel_vec_u8();
    let _ = b.peel_vec_address();
    let _ = b.peel_option_address();
    if (!b.peel_bool()) return vector[];
    let _ = b.peel_address();
    let _ = b.peel_vec_u8();
    let _ = b.peel_vec_u8();
    b.peel_vec_u8()
}

fun url_host(url: &vector<u8>): vector<u8> {
    let scheme = HTTPS_SCHEME;
    let n = scheme.length();
    if (url.length() < n) return vector[];
    let mut i = 0;
    while (i < n) {
        if (ascii_lower(url[i]) != scheme[i]) return vector[];
        i = i + 1;
    };
    let mut host = vector[];
    while (i < url.length()) {
        let c = url[i];
        if (c == 0x2f || c == 0x3f || c == 0x23) break;
        host.push_back(ascii_lower(c));
        i = i + 1;
    };
    host
}

fun ascii_lower(c: u8): u8 {
    if (c >= 0x41 && c <= 0x5a) c + 32 else c
}

fun is_valid_host(host: &vector<u8>): bool {
    let n = host.length();
    if (n == 0 || n > MAX_HOST_LEN) return false;
    let mut i = 0;
    while (i < n) {
        let c = host[i];
        let ok = (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x2e || c == 0x2d;
        if (!ok) return false;
        i = i + 1;
    };
    true
}

#[test_only]
public fun assembly_type_id_for_testing(assembly: &Assembly): u64 { assembly_type_id(assembly) }

#[test_only]
public fun storage_unit_type_id_for_testing(su: &StorageUnit): u64 {
    let mut b = bcs::new(std::bcs::to_bytes(su));
    peel_type_id(&mut b)
}

#[test_only]
public fun storage_unit_url_for_testing(su: &StorageUnit): vector<u8> { storage_unit_url(su) }

#[test_only]
public fun url_host_for_testing(url: vector<u8>): vector<u8> { url_host(&url) }
