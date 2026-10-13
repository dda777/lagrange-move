module academy_triex_v0::triex_v0;

use academy_core::core::{Self, ClaimTicket, Requirement};
use std::internal;
use triex::trading_account::{Self, TradingAccount};

#[error(code = 190)]
const ENotAccountOwner: vector<u8> = b"Trading account does not belong to the player";
#[error(code = 191)]
const ENoTrades: vector<u8> = b"Trading account has no executed trades in the turnover window";

public struct TriexTrade has drop {}

public fun triex_trade(): Requirement {
    core::requirement(TriexTrade {})
}

public fun check_triex_trade<Q>(t: &mut ClaimTicket, account: &TradingAccount, ctx: &TxContext) {
    let turnover = trading_account::fee_turnover<Q>(account, ctx);
    check(t, trading_account::owner(account), trading_account::id(account), turnover, ctx);
}

fun check(t: &mut ClaimTicket, owner: address, account_id: ID, turnover: u128, ctx: &TxContext) {
    let _ = t.take_check(internal::permit<TriexTrade>());
    assert!(owner == ctx.sender() && owner == t.claim_recipient(), ENotAccountOwner);
    assert!(turnover > 0, ENoTrades);
    t.add_evidence(internal::permit<TriexTrade>(), account_id);
}

#[test_only]
public fun check_triex_trade_with_turnover_for_testing(
    t: &mut ClaimTicket,
    account: &TradingAccount,
    turnover: u128,
    ctx: &TxContext,
) {
    check(t, trading_account::owner(account), trading_account::id(account), turnover, ctx);
}
