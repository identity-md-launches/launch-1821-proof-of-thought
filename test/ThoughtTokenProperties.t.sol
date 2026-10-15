// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ThoughtToken} from "../src/ThoughtToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TokenPropertyBase} from "./TokenPropertyBase.sol";

/// @dev Extends the existing examples with boundary and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract ThoughtTokenPropertiesTest is TokenPropertyBase {
    // Local test identities only; no production configuration is required.
    address private constant ALICE = address(0x10001);
    address private constant BOB = address(0x10002);
    address private constant SPENDER = address(0x10003);
    ThoughtToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new ThoughtToken();
    }

    function test_oneSmallestUnitTransfersWithoutRounding() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_maximumTransferRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), EXPECTED_SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_maximumDelegatedTransferRevertsWithoutConsumingInfiniteAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), EXPECTED_SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - 1);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        token.transfer(ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(ALICE);
        token.transfer(ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_ownerTransferFromNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_approvalToRecipientDoesNotAuthorizeAnotherCaller() public {
        token.approve(ALICE, EXPECTED_SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), ALICE), EXPECTED_SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_spenderCanBeRecipientWithoutChangingItsOwnAllowance() public {
        token.approve(SPENDER, 7);
        vm.prank(SPENDER);
        token.approve(address(this), 3);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), SPENDER, 7));
        assertEq(token.balanceOf(SPENDER), 7);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - 7);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.allowance(SPENDER, address(this)), 3);
    }

    function test_consumedAllowanceCannotBeReplayed() public {
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_zeroSpenderCannotBeApprovedEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY);
    }

    function testFuzz_roundTripRestoresExistingBalances(uint256 aliceFunds, uint256 bobFunds, uint256 amount) public {
        aliceFunds = bound(aliceFunds, 0, EXPECTED_SUPPLY);
        bobFunds = bound(bobFunds, 0, EXPECTED_SUPPLY - aliceFunds);
        amount = bound(amount, 0, aliceFunds);
        token.transfer(ALICE, aliceFunds);
        token.transfer(BOB, bobFunds);
        vm.prank(ALICE);
        token.approve(SPENDER, 7);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), aliceFunds - amount);
        assertEq(token.balanceOf(BOB), bobFunds + amount);
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), aliceFunds);
        assertEq(token.balanceOf(BOB), bobFunds);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - aliceFunds - bobFunds);
        assertEq(token.allowance(ALICE, SPENDER), 7);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_delegatedSelfTransferPreservesBalanceButSpendsAllowance(
        uint256 funds,
        uint256 approved,
        uint256 amount
    ) public {
        funds = bound(funds, 0, EXPECTED_SUPPLY);
        amount = bound(amount, 0, min(funds, approved));
        token.transfer(ALICE, funds);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, ALICE, amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, ALICE, amount));
        assertEq(token.balanceOf(ALICE), funds);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - funds);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_approvalsOverwriteAndAreIsolated(uint256 first, uint256 second) public {
        token.approve(SPENDER, first);
        token.approve(BOB, first);
        vm.prank(ALICE);
        token.approve(SPENDER, first);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, second);
        assertTrue(token.approve(SPENDER, second));
        assertEq(token.allowance(address(this), SPENDER), second);
        assertEq(token.allowance(address(this), BOB), first);
        assertEq(token.allowance(ALICE, SPENDER), first);
        assertEq(token.allowance(SPENDER, address(this)), 0);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_insufficientAllowanceIsAtomic(uint256 funds, uint256 approved, uint256 amount) public {
        funds = bound(funds, 1, EXPECTED_SUPPLY);
        approved = bound(approved, 0, funds - 1);
        amount = bound(amount, approved + 1, funds);
        token.transfer(ALICE, funds);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        _assertUnchanged(funds, approved);
    }

    function testFuzz_insufficientBalanceRestoresFiniteAllowance(uint256 funds, uint256 amount, uint256 approved)
        public
    {
        funds = bound(funds, 0, EXPECTED_SUPPLY);
        amount = bound(amount, funds + 1, type(uint256).max - 1);
        approved = bound(approved, amount, type(uint256).max - 1);
        token.transfer(ALICE, funds);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, funds, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        _assertUnchanged(funds, approved);
    }

    function testFuzz_invalidReceiverRestoresAllowance(uint256 approved, uint256 amount, bool infinite) public {
        if (infinite) approved = type(uint256).max;
        amount = bound(amount, 0, min(EXPECTED_SUPPLY, approved));
        token.transfer(ALICE, EXPECTED_SUPPLY);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), amount);
        _assertUnchanged(EXPECTED_SUPPLY, approved);
    }

    function testFuzz_infiniteApprovalCanBeSpentRepeatedlyThenRevoked(uint256 first, uint256 second) public {
        first = bound(first, 0, EXPECTED_SUPPLY);
        second = bound(second, 0, EXPECTED_SUPPLY - first);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, second));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), second);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - first - second);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_zeroSpenderRevertsWithoutChangingOtherApproval(uint256 approved) public {
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), approved);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_zeroValueTransfersPreserveBalancesAndAllowance(uint256 funds, uint256 approved) public {
        funds = bound(funds, 0, EXPECTED_SUPPLY);
        token.transfer(ALICE, funds);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, ALICE, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(ALICE, 0));
        _assertUnchanged(funds, approved);
    }

    function testFuzz_transferToTokenContractIsAccountedFor(uint256 amount) public {
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        assertTrue(token.transfer(address(token), amount));
        assertEq(token.balanceOf(address(token)), amount);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - amount);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function _assertUnchanged(uint256 aliceFunds, uint256 approved) private view {
        assertEq(token.balanceOf(ALICE), aliceFunds);
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - aliceFunds);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }
}
