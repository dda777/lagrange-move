module academy_core::verified_checks;

use academy_core::core::Requirement;
use std::type_name::{Self, TypeName};
use sui::{event, vec_set::{Self, VecSet}};

const VERSION: u64 = 1;

#[error(code = 1)]
const EWrongVersion: vector<u8> = b"VerifiedChecks version does not match the package version";
#[error(code = 24)]
const EAlreadyVerified: vector<u8> = b"Module type is already verified";
#[error(code = 25)]
const ENotVerified: vector<u8> = b"Module type is not verified";
#[error(code = 26)]
const EAlreadyMigrated: vector<u8> = b"VerifiedChecks is already at the current package version";

public struct PlatformAdminCap has key, store { id: UID }

public struct VerifiedChecks has key {
    id: UID,
    version: u64,
    checks: VecSet<TypeName>,
}

public struct VerifiedCheckAdded has copy, drop { type_name: TypeName }

public struct VerifiedCheckRemoved has copy, drop { type_name: TypeName }

fun init(ctx: &mut TxContext) {
    transfer::share_object(VerifiedChecks {
        id: object::new(ctx),
        version: VERSION,
        checks: vec_set::empty(),
    });
    transfer::public_transfer(PlatformAdminCap { id: object::new(ctx) }, ctx.sender());
}

public fun add<T>(vc: &mut VerifiedChecks, _: &PlatformAdminCap) {
    assert!(vc.version == VERSION, EWrongVersion);
    let t = type_name::with_original_ids<T>();
    assert!(!vc.checks.contains(&t), EAlreadyVerified);
    vc.checks.insert(t);
    event::emit(VerifiedCheckAdded { type_name: t });
}

public fun remove<T>(vc: &mut VerifiedChecks, _: &PlatformAdminCap) {
    assert!(vc.version == VERSION, EWrongVersion);
    let t = type_name::with_original_ids<T>();
    assert!(vc.checks.contains(&t), ENotVerified);
    vc.checks.remove(&t);
    event::emit(VerifiedCheckRemoved { type_name: t });
}

public fun migrate(vc: &mut VerifiedChecks, _: &PlatformAdminCap) {
    assert!(vc.version < VERSION, EAlreadyMigrated);
    vc.version = VERSION;
}

public fun is_verified<T>(vc: &VerifiedChecks): bool {
    is_type_verified(vc, &type_name::with_original_ids<T>())
}

public fun is_type_verified(vc: &VerifiedChecks, t: &TypeName): bool {
    assert!(vc.version == VERSION, EWrongVersion);
    vc.checks.contains(t)
}

public fun is_requirement_verified(vc: &VerifiedChecks, r: &Requirement): bool {
    is_type_verified(vc, &r.requirement_type())
}

public fun verified_types(vc: &VerifiedChecks): vector<TypeName> { vc.checks.into_keys() }

public fun version(vc: &VerifiedChecks): u64 { vc.version }

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx) }

#[test_only]
public fun set_version_for_testing(vc: &mut VerifiedChecks, version: u64) { vc.version = version; }
