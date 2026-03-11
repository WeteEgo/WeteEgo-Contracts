// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {WeteEgoGatewayV2} from "../src/WeteEgoGatewayV2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WeteEgoGatewayV2Test is Test {
    event OrderCreated(bytes32 indexed orderId, address indexed sender, address token, uint256 amount, bytes32 settlementRef, uint256 expiresAt);
    event OrderSettled(bytes32 indexed orderId, address indexed settler, uint256 settledAt);
    event OrderRefunded(bytes32 indexed orderId, address indexed refundedTo, uint256 refundedAt);
    event SettlementAddressUpdated(address indexed previous, address indexed current);
    event SettlerUpdated(address indexed previous, address indexed current);
    event MaxOrderAmountUpdated(uint256 previous, uint256 current);
    event EmergencyPaused(address indexed by);
    event EmergencyUnpaused(address indexed by);
    event ParameterExecuted(string indexed param, bytes value);

    WeteEgoGatewayV2 public gateway;
    TimelockController public timelock;
    MockERC20 public token;

    address public multisig;   // pauser + proposer/executor
    address public settler;
    address public settlement;
    address public user;

    uint256 public constant MIN_DELAY = 24 hours;

    bytes32 constant ORDER_ID = keccak256("order-1");
    bytes32 constant SETTLEMENT_REF = keccak256("ref");

    function setUp() public {
        multisig = makeAddr("multisig");
        settler = makeAddr("settler");
        settlement = makeAddr("settlement");
        user = makeAddr("user");

        // TimelockController: minDelay, proposers[], executors[], canceler (optional)
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;

        timelock = new TimelockController(MIN_DELAY, proposers, executors, multisig);

        gateway = new WeteEgoGatewayV2(
            settlement,
            settler,
            1000e6,              // max 1000 USDC per order
            address(timelock),
            multisig
        );

        token = new MockERC20();
        token.mint(user, 10000e6);
    }

    function test_createOrder_escrowsTokens() public {
        uint256 amount = 100e6;
        vm.startPrank(user);
        token.approve(address(gateway), amount);
        gateway.createOrder(IERC20(address(token)), amount, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        assertEq(token.balanceOf(address(gateway)), amount);
        (, , , , WeteEgoGatewayV2.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 1);
    }

    function test_createOrder_revertsWhenExceedsMaxOrderAmount() public {
        vm.startPrank(user);
        token.approve(address(gateway), 2000e6);
        vm.expectRevert(WeteEgoGatewayV2.ExceedsMaxOrderAmount.selector);
        gateway.createOrder(IERC20(address(token)), 2000e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
    }

    function test_createOrder_allowsExactlyMaxOrderAmount() public {
        uint256 amount = 1000e6;
        vm.startPrank(user);
        token.approve(address(gateway), amount);
        gateway.createOrder(IERC20(address(token)), amount, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
        (, , , , WeteEgoGatewayV2.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 1);
    }

    function test_settleOrder_releasesEscrow() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.prank(settler);
        gateway.settleOrder(ORDER_ID, "");

        assertEq(token.balanceOf(settlement), 100e6);
        (, , , , WeteEgoGatewayV2.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 2);
    }

    function test_pause_blocksCreateOrder() public {
        vm.prank(multisig);
        gateway.pause();

        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        vm.expectRevert();
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
    }

    function test_pause_emitsEmergencyPaused() public {
        vm.expectEmit(true, true, false, true);
        emit EmergencyPaused(multisig);
        vm.prank(multisig);
        gateway.pause();
    }

    function test_unpause_allowsCreateOrderAgain() public {
        vm.prank(multisig);
        gateway.pause();
        vm.prank(multisig);
        gateway.unpause();

        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
        (, , , , WeteEgoGatewayV2.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 1);
    }

    function test_onlyPauserCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        gateway.pause();
    }

    function test_timelock_setSettlementAddress_afterDelay() public {
        address newSettlement = makeAddr("newSettlement");

        vm.prank(multisig);
        timelock.schedule(
            address(gateway),
            0,
            abi.encodeWithSelector(gateway.setSettlementAddress.selector, newSettlement),
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(multisig);
        timelock.execute(
            address(gateway),
            0,
            abi.encodeWithSelector(gateway.setSettlementAddress.selector, newSettlement),
            bytes32(0),
            bytes32(0)
        );

        assertEq(gateway.settlementAddress(), newSettlement);
    }

    function test_timelock_setSettlementAddress_revertsBeforeDelay() public {
        address newSettlement = makeAddr("newSettlement");

        vm.prank(multisig);
        timelock.schedule(
            address(gateway),
            0,
            abi.encodeWithSelector(gateway.setSettlementAddress.selector, newSettlement),
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + MIN_DELAY - 1);

        vm.prank(multisig);
        vm.expectRevert();
        timelock.execute(
            address(gateway),
            0,
            abi.encodeWithSelector(gateway.setSettlementAddress.selector, newSettlement),
            bytes32(0),
            bytes32(0)
        );
    }

    function test_timelock_setMaxOrderAmount_afterDelay() public {
        uint256 newMax = 2000e6;

        vm.prank(multisig);
        timelock.schedule(
            address(gateway),
            0,
            abi.encodeWithSelector(gateway.setMaxOrderAmount.selector, newMax),
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(multisig);
        timelock.execute(
            address(gateway),
            0,
            abi.encodeWithSelector(gateway.setMaxOrderAmount.selector, newMax),
            bytes32(0),
            bytes32(0)
        );

        assertEq(gateway.maxOrderAmount(), newMax);
    }

    function test_multisigCannotSetSettlementDirectly() public {
        vm.prank(multisig);
        vm.expectRevert();
        gateway.setSettlementAddress(makeAddr("newSettlement"));
    }

    function test_refundOrder_afterTimeout() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 minutes + 1);
        gateway.refundOrder(ORDER_ID);

        assertEq(token.balanceOf(user), 10000e6);
        (, , , , WeteEgoGatewayV2.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 3);
    }

    function testFuzz_createAndSettle(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1000e6));
        token.mint(user, amount);
        bytes32 id = keccak256(abi.encode(amount, block.timestamp));

        vm.startPrank(user);
        token.approve(address(gateway), amount);
        gateway.createOrder(IERC20(address(token)), amount, id, SETTLEMENT_REF);
        vm.stopPrank();

        vm.prank(settler);
        gateway.settleOrder(id, "");

        assertEq(token.balanceOf(settlement), amount);
        (, , , , WeteEgoGatewayV2.OrderStatus status) = gateway.orders(id);
        assertEq(uint256(status), 2);
    }

    function testFuzz_maxOrderAmountEnforced(uint256 amount) public {
        amount = bound(amount, 1001e6, 100_000e6); // above max 1000e6, but safe for mint
        token.mint(user, amount);
        bytes32 id = keccak256(abi.encode(amount));

        vm.startPrank(user);
        token.approve(address(gateway), amount);
        vm.expectRevert(WeteEgoGatewayV2.ExceedsMaxOrderAmount.selector);
        gateway.createOrder(IERC20(address(token)), amount, id, SETTLEMENT_REF);
        vm.stopPrank();
    }
}
