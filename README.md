# PROOF OF THOUGHT (THOUGHT)

`src/ThoughtToken.sol:ThoughtToken` is a fixed-supply ERC-20 using the vendored
OpenZeppelin Contracts v5.0.2 implementation.

| Property | Value |
| --- | --- |
| Name | `PROOF OF THOUGHT` |
| Symbol | `THOUGHT` |
| Decimals | `18` |
| Whole-token supply | `10,000,011` |
| Supply in smallest units | `10000011000000000000000000` |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | `0` |
| Initial recipient | Constructor's `msg.sender` |

The constructor mints the entire supply once and emits
`Transfer(address(0), msg.sender, 10000011000000000000000000)`. When a factory
deploys the token, the factory receives every token; the wallet calling the
factory receives none automatically. The token does not use `tx.origin`.

## Behavior and assumptions

The brief specifies metadata and a fixed supply, so transfers use ordinary
ERC-20 semantics. There are no transfer taxes, fees, rebases, burns, owner,
administrators, pause or blacklist controls, upgrade mechanism, or callable mint
function. The internal OpenZeppelin mint function is used only in construction.
`INITIAL_SUPPLY` is a public constant in smallest units. Supply stays constant
after deployment.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
OpenZeppelin's ERC-6093 custom errors on failure. Transfers require sufficient
balance; delegated transfers also require allowance. Zero-value transfers to
nonzero addresses are supported. Sending tokens to the zero address or approving
the zero spender is rejected. Self-transfers preserve balances.

Finite allowances decrease on spending. An allowance of `type(uint256).max`
remains unchanged on spending, following OpenZeppelin's standard unlimited
allowance behavior. `approve` emits `Approval`; `transferFrom` emits `Transfer`
without an additional `Approval` event for allowance consumption. Indexers should
query `allowance` for the current allowance.

## Build and check

Foundry and Solidity 0.8.26 must be available. All Solidity dependencies are
ordinary files under `lib/`; no dependency installation, submodule, network
access, environment configuration, FFI, or filesystem cheatcodes are needed to
build or run the tests once that compiler is installed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x3c6afec03e1365af8c5420b59381736debe455cfcb7093615ea73808f9d89f41 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer with 200 runs,
and `bytecode_hash = "none"`. Tests use 512 cases per fuzz test and do not read or
change environment variables. The shell seed above controls Foundry's runner.

The 29 tests cover exact metadata and minting, constructor and transfer events,
factory deployment, full-supply and zero/self transfers, approvals and revocation,
finite and unlimited allowances, invalid addresses, insufficient balances and
allowances, revert atomicity, absence of common administrative entry points,
runtime opcode restrictions, exact launch-style distribution, and conservation
of supply across transfers and fuzzed sequences of 32 transfers. The local
launch-style test models token movements, not Uniswap execution. The supplied
protected harness remains the independent check of actual launch infrastructure.

## Deployment and operation

The production deployment target is **ThoughtToken**, not either test helper.
The contract name is 12 characters and its bytecode needs no library linking.
Creation bytecode and ABI are built at `out/ThoughtToken.sol/ThoughtToken.json`.
Deploy that creation bytecode with no appended constructor arguments and zero
native-currency value. The constructor does not call external contracts and
requires no pre-existing chain state. Ethereum is the intended launch chain;
the configured bytecode requires a Cancun-compatible EVM.

The launch operator is responsible for deploying through the intended factory,
confirming the token's metadata and exact supply, and distributing tokens held by
the factory according to the launch's policy. Distributor, pool, pricing, pair,
and allocation logic belong to that infrastructure and are not implemented by
the token. The token sends no allocations in its constructor beyond the full
mint to the deployer. The separate launch process supplies the manifest; this
project needs no owner, recipient address, or other configuration parameter.

After launch there are no setters or maintenance calls. The operator should
publish the deployed address and verify the source with the pinned compiler and
settings. Holders control their tokens and approvals; the deployer retains no
authority over other holders. Prefer exact allowances, and revoke existing
allowances before changing a nonzero allowance to mitigate ERC-20 approval
transaction-ordering races. Sending tokens to this token contract or another
contract unable to transfer them back can lock them permanently; there is no
administrative recovery function. The contract does not accept ordinary native
currency payments and cannot recover forced native currency or unrelated tokens.

Local validation consists of Foundry build, unit tests, fuzz tests and formatting,
plus source review against the supplied security reference. Slither, Mythril,
production transactions and block-explorer verification are not part of these
local checks. Tests do not constitute an independent security audit; independent
review and deployment verification remain release responsibilities.
