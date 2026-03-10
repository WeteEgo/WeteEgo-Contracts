// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {WeteEgoRouter} from "../src/WeteEgoRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal ERC20 mock for testing.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WeteEgoRouterTest is Test {
    event SwapForwarded(address indexed sender, address indexed token, uint256 amount, bytes32 settlementRef, uint256 timestamp);
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);

    WeteEgoRouter public router;
    MockERC20 public token;

    address public settlement = makeAddr("settlement");
    address public user = makeAddr("user");
    address public other = makeAddr("other");

    bytes32 public constant REF = keccak256(abi.encode("test-order-1"));

    function setUp() public {
        router = new WeteEgoRouter(settlement);
        token = new MockERC20();
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    function test_constructor_setsSettlement() public view {
        assertEq(router.settlement(), settlement);
    }

    function test_constructor_setsOwner() public view {
        assertEq(router.owner(), address(this));
    }

    function test_constructor_revertsOnZeroSettlement() public {
        vm.expectRevert(WeteEgoRouter.ZeroAddress.selector);
        new WeteEgoRouter(address(0));
    }

    // ─── forwardERC20 ─────────────────────────────────────────────────────────

    function test_forwardERC20_transfersTokensToSettlement() public {
        uint256 amount = 100e6; // 100 USDC
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(router), amount);
        router.forwardERC20(IERC20(address(token)), amount, REF);
        vm.stopPrank();

        assertEq(token.balanceOf(settlement), amount);
        assertEq(token.balanceOf(user), 0);
    }

    function test_forwardERC20_emitsSwapForwardedEvent() public {
        uint256 amount = 50e6;
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(router), amount);

        vm.expectEmit(true, true, false, true);
        emit SwapForwarded(user, address(token), amount, REF, block.timestamp);

        router.forwardERC20(IERC20(address(token)), amount, REF);
        vm.stopPrank();
    }

    function test_forwardERC20_revertsOnZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(WeteEgoRouter.ZeroAmount.selector);
        router.forwardERC20(IERC20(address(token)), 0, REF);
    }

    function test_forwardERC20_revertsOnZeroAddressToken() public {
        vm.prank(user);
        vm.expectRevert(WeteEgoRouter.ZeroAddress.selector);
        router.forwardERC20(IERC20(address(0)), 100e6, REF);
    }

    function test_forwardERC20_revertsWithoutApproval() public {
        token.mint(user, 100e6);
        vm.prank(user);
        vm.expectRevert();
        router.forwardERC20(IERC20(address(token)), 100e6, REF);
    }

    // ─── forwardETH ───────────────────────────────────────────────────────────

    function test_forwardETH_transfersEthToSettlement() public {
        uint256 amount = 1 ether;
        vm.deal(user, amount);

        vm.prank(user);
        router.forwardETH{value: amount}(REF);

        assertEq(settlement.balance, amount);
    }

    function test_forwardETH_emitsSwapForwardedEvent() public {
        uint256 amount = 0.5 ether;
        vm.deal(user, amount);

        vm.expectEmit(true, true, false, true);
        emit SwapForwarded(user, address(0), amount, REF, block.timestamp);

        vm.prank(user);
        router.forwardETH{value: amount}(REF);
    }

    function test_forwardETH_revertsOnZeroValue() public {
        vm.prank(user);
        vm.expectRevert(WeteEgoRouter.ZeroAmount.selector);
        router.forwardETH{value: 0}(REF);
    }

    // ─── setOwner ─────────────────────────────────────────────────────────────

    function test_setOwner_updatesOwner() public {
        router.setOwner(other);
        assertEq(router.owner(), other);
    }

    function test_setOwner_emitsOwnerUpdatedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit OwnerUpdated(address(this), other);
        router.setOwner(other);
    }

    function test_setOwner_revertsIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(WeteEgoRouter.OnlyOwner.selector);
        router.setOwner(other);
    }

    function test_setOwner_revertsOnZeroAddress() public {
        vm.expectRevert(WeteEgoRouter.ZeroAddress.selector);
        router.setOwner(address(0));
    }

    // ─── Fuzz tests ───────────────────────────────────────────────────────────

    function testFuzz_forwardERC20(uint96 amount, bytes32 ref) public {
        vm.assume(amount > 0);

        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(router), amount);
        router.forwardERC20(IERC20(address(token)), amount, ref);
        vm.stopPrank();

        assertEq(token.balanceOf(settlement), amount);
    }

    function testFuzz_forwardETH(uint96 amount, bytes32 ref) public {
        vm.assume(amount > 0);
        vm.deal(user, amount);

        vm.prank(user);
        router.forwardETH{value: amount}(ref);

        assertEq(settlement.balance, amount);
    }
}
