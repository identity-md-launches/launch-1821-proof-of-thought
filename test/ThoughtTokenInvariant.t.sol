// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ThoughtToken} from "../src/ThoughtToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TokenPropertyBase} from "./TokenPropertyBase.sol";

/// @dev All inputs stay within a closed set of holders. The token itself is an
/// additional recipient, tracked as a sink, never impersonated as a spender.
contract ThoughtTokenHandler is TokenPropertyBase {
    ThoughtToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public calls;

    constructor() {
        token = new ThoughtToken();
        actors = [address(this), address(0x20001), address(0x20002), address(0x20003), address(0x20004)];
        require(token.balanceOf(address(this)) == EXPECTED_SUPPLY, "constructor allocation");
        expectedBalance[address(this)] = EXPECTED_SUPPLY;
        // Fund all actors using real transfers, never storage writes or token deal.
        for (uint256 i = 1; i < actors.length; ++i) {
            _transfer(actors[0], actors[i], EXPECTED_SUPPLY / actors.length);
        }
        // Seed both finite and infinite approvals so spending is reachable from
        // the first random action. Later approvals, revocations and spends persist.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % actors.length], EXPECTED_SUPPLY / 10);
            _approve(actors[i], actors[(i + 2) % actors.length], type(uint256).max);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), _amount(amountSeed, expectedBalance[from]));
        ++calls;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 mode = amountSeed % 6;
        uint256 amount = mode == 0
            ? 0
            : mode == 1
                ? 1
                : mode == 2
                    ? EXPECTED_SUPPLY
                    : mode == 3 ? type(uint256).max : mode == 4 ? type(uint256).max - 1 : amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
        ++calls;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), 0);
        ++calls;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 amount = _amount(amountSeed, min(expectedBalance[owner], approved));
        vm.prank(spender);
        require(token.transferFrom(owner, to, amount), "transferFrom returned false");
        _recordTransfer(owner, to, amount);
        if (approved != type(uint256).max) expectedAllowance[owner][spender] = approved - amount;
        ++calls;
    }

    function transferToToken(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, address(token), _amount(amountSeed, expectedBalance[from]));
        ++calls;
    }

    function rejectOverdraw(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
        ++calls;
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 approved = expectedAllowance[owner][spender];
        // An infinite approval cannot be exceeded; revoke it before attempting theft.
        if (approved == type(uint256).max) {
            _approve(owner, spender, 0);
            approved = 0;
        }
        uint256 amount = bound(amountSeed, approved + 1, type(uint256).max);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        ++calls;
    }

    function rejectOverdrawAfterApproval(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        // Enough allowance, insufficient funds: the allowance deduction must roll back.
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
        ++calls;
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = expectedBalance[owner];
        if (delegated) limit = min(limit, expectedAllowance[owner][spender]);
        uint256 amount = _amount(amountSeed, limit);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _reject(
            delegated ? spender : owner,
            data,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        ++calls;
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        ++calls;
    }

    function rejectSupplyChange(uint256 callerSeed, uint256 recipientSeed, uint256 amount, uint256 mode) external {
        address recipient = _actor(recipientSeed);
        bytes memory data;
        if (mode % 4 == 0) data = abi.encodeWithSignature("mint(address,uint256)", recipient, amount);
        else if (mode % 4 == 1) data = abi.encodeWithSignature("burn(uint256)", amount);
        else if (mode % 4 == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", recipient, amount);
        else data = abi.encodeWithSignature("initialize(address)", recipient);
        vm.prank(_actor(callerSeed));
        (bool success,) = address(token).call(data);
        require(!success, "unexpected supply-changing entry point");
        ++calls;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    /// @dev Bias valid calls toward zero, full balance/allowance and one wei.
    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 8 == 0) return 0;
        if (seed % 8 == 1) return maximum;
        if (seed % 8 == 2) return min(1, maximum);
        return bound(seed, 0, maximum);
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        require(token.transfer(to, amount), "transfer returned false");
        _recordTransfer(from, to, amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        // Ghosts depend only on requested actions, never on observed token balances.
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        require(token.approve(spender, amount), "approve returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        require(!success, "invalid action succeeded");
        require(keccak256(reason) == keccak256(expectedError), "unexpected rejection reason");
        // Ghosts deliberately remain unchanged. The invariants check atomic rollback
        // for every holder and allowance, including accounts unrelated to this call.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract ThoughtTokenInvariantTest is TokenPropertyBase {
    ThoughtTokenHandler private handler;
    ThoughtToken private token;

    // Foundry's invariant discovery ABI, supplied locally to avoid a new dependency.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        handler = new ThoughtTokenHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.revoke.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.transferToToken.selector;
        selectors[5] = handler.rejectOverdraw.selector;
        selectors[6] = handler.rejectExcessAllowance.selector;
        selectors[7] = handler.rejectOverdrawAfterApproval.selector;
        selectors[8] = handler.rejectZeroRecipient.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        selectors[10] = handler.rejectSupplyChange.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_supplyAndMetadataNeverChange() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.name(), "PROOF OF THOUGHT");
        assertEq(token.symbol(), "THOUGHT");
        assertEq(token.decimals(), 18);
    }

    function invariant_allSupplyRemainsAccountedFor() public view {
        uint256 sum = token.balanceOf(address(token));
        for (uint256 i; i < 5; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_eachHolderMatchesTheIndependentLedger() public view {
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            require(token.balanceOf(actor) == handler.expectedBalance(actor), "holder ledger mismatch");
        }
        require(token.balanceOf(address(token)) == handler.expectedBalance(address(token)), "sink ledger mismatch");
    }

    function invariant_onlyTheApprovedSpenderCanConsumeItsAllowance() public view {
        for (uint256 i; i < 5; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(owner, spender) == handler.expectedAllowance(owner, spender),
                    "allowance ledger mismatch"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            assertEq(token.allowance(address(token), owner), 0);
            assertEq(token.allowance(owner, address(token)), 0);
        }
    }

    function afterInvariant() public {
        require(handler.calls() > 0, "no handler actions executed");
        // Every controlled holder must still be able to transfer its entire balance
        // after an arbitrary sequence, including rejected calls and revocations.
        for (uint256 i = 1; i < 5; ++i) {
            handler.transfer(i, 0, 1);
        }
        handler.transfer(0, 1, 1);
        handler.transfer(1, 0, 1);
        assertEq(token.balanceOf(handler.actors(0)), EXPECTED_SUPPLY - handler.expectedBalance(address(token)));
        for (uint256 i = 1; i < 5; ++i) {
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        invariant_supplyAndMetadataNeverChange();
        invariant_allSupplyRemainsAccountedFor();
        invariant_eachHolderMatchesTheIndependentLedger();
        invariant_onlyTheApprovedSpenderCanConsumeItsAllowance();
    }

    function test_handlerExercisesSpendingRevocationAndFailureRollback() public {
        uint256 funds = EXPECTED_SUPPLY / 5;
        // Spend all of a seeded finite approval, then try to spend it again.
        handler.transferFrom(1, 2, 3, 1);
        assertEq(token.balanceOf(handler.actors(1)), funds - EXPECTED_SUPPLY / 10);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 0);
        handler.rejectExcessAllowance(1, 2, 3, 1);
        // The same owner has an independent infinite approval for actor 3.
        handler.transferFrom(1, 3, 1, 2);
        assertEq(token.allowance(handler.actors(1), handler.actors(3)), type(uint256).max);
        handler.revoke(1, 3);
        handler.rejectExcessAllowance(1, 3, 0, 1);
        handler.rejectOverdrawAfterApproval(1, 3, 0, type(uint256).max, false);
        handler.rejectZeroRecipient(1, 3, 1, true);
        handler.rejectZeroSpender(1, 0);
        handler.rejectOverdraw(1, 1, type(uint256).max);
        handler.rejectSupplyChange(0, 1, EXPECTED_SUPPLY, 0);
        handler.approve(1, 3, 1);
        handler.transferFrom(1, 3, 3, 1);
        handler.transferToToken(2, 2);
        assertEq(token.balanceOf(address(token)), 1);
        afterInvariant();
    }
}
