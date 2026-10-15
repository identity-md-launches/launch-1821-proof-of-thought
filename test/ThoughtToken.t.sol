// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ThoughtToken} from "../src/ThoughtToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./TestBase.sol";

/// @dev Models a factory creating a token, without involving any launch infrastructure.
contract TokenDeployer {
    function deploy() external returns (ThoughtToken) {
        return new ThoughtToken();
    }
}

contract ThoughtTokenTest is TestBase {
    uint256 private constant SUPPLY = 10_000_011_000_000_000_000_000_000;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    ThoughtToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new ThoughtToken();
    }

    function test_metadataAndExactSupply() public view {
        assertEq(token.name(), "PROOF OF THOUGHT");
        assertEq(token.symbol(), "THOUGHT");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsFullMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new ThoughtToken();
    }

    function test_factoryReceivesEntireSupplyInsteadOfExternalCaller() public {
        TokenDeployer factory = new TokenDeployer();
        vm.prank(ALICE);
        ThoughtToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 123 ether);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanBeTransferredAndReturned() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferOverBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_emptyAccountCannotTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_approveOverwriteAndRevokeEmitEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 50));
        assertEq(token.allowance(address(this), SPENDER), 50);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromUsesAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 60));
        assertEq(token.allowance(address(this), SPENDER), 40);
        assertEq(token.balanceOf(ALICE), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 40));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 40);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromOverAllowanceRevertsAtomically() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 11);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_failedTransferFromRestoresSpentAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToZeroRestoresAllowance() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroSenderReverts() public {
        // Allowance accounting checks the approver before transfer checks the sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_infiniteAllowanceRemainsUnchanged() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_revokedSpenderCannotTransfer() public {
        token.approve(SPENDER, 100);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_deployerCannotSpendUnapprovedHolderBalance() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(ALICE, 100);
        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[7] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[8] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[9] = abi.encodeWithSignature("seize(address)", ALICE);
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call(calls[i]);
            assertTrue(!success);
            vm.prank(BOB);
            (success,) = address(token).call(calls[i]);
            assertTrue(!success);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
    }

    function test_launchStyleDistributionAndRoundTripHaveNoDeductions() public {
        // These are test participants, not configured production infrastructure.
        address distributor = address(0xD157);
        address pool = address(0x9001);
        uint256 swarm = SUPPLY * 10 / 100;
        uint256 liquidity = SUPPLY * 88 / 100;
        uint256 remainder = SUPPLY - swarm - liquidity;
        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(pool, liquidity));
        assertTrue(token.transfer(BOB, remainder));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(pool), liquidity);
        assertEq(token.balanceOf(BOB), remainder);
        vm.prank(distributor);
        assertTrue(token.transfer(ALICE, swarm));
        vm.prank(pool);
        assertTrue(token.transfer(ALICE, 1 ether));
        vm.prank(ALICE);
        assertTrue(token.transfer(pool, 1 ether));
        assertEq(token.balanceOf(ALICE), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(pool), liquidity);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeContainsNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 rawAmount) public {
        // Treat the zero-address failure and self-transfer behavior separately above.
        if (recipient == address(0) || recipient == address(this)) return;
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndSpendsAllowance(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowance = rawAllowance % (SUPPLY + 1);
        uint256 amount = rawAmount % (allowance + 1);
        token.approve(SPENDER, allowance);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), allowance - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overdrawAlwaysReverts(uint256 rawExcess) public {
        uint256 amount = SUPPLY + 1 + rawExcess % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferSequenceConservesAllBalances(bytes32 seed) public {
        address[4] memory actors = [address(this), ALICE, BOB, SPENDER];
        for (uint256 i; i < 32; ++i) {
            seed = keccak256(abi.encode(seed, i));
            uint256 random = uint256(seed);
            address from = actors[random % 4];
            address to = actors[(random >> 8) % 4];
            uint256 amount = (random >> 16) % (token.balanceOf(from) + 1);
            vm.prank(from);
            assertTrue(token.transfer(to, amount));
            uint256 sum;
            for (uint256 j; j < actors.length; ++j) {
                sum += token.balanceOf(actors[j]);
            }
            assertEq(sum, SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
        }
    }
}
