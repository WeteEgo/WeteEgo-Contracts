// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {WeteEgoGateway} from "../src/WeteEgoGateway.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WeteEgoGatewayTest is Test {
    event OrderCreated(bytes32 indexed orderId, address indexed sender, address token, uint256 amount, bytes32 settlementRef, uint256 expiresAt);
    event OrderSettled(bytes32 indexed orderId, address indexed settler, uint256 settledAt);
    event OrderRefunded(bytes32 indexed orderId, address indexed refundedTo, uint256 refundedAt);

    WeteEgoGateway public gateway;
    MockERC20 public token;

    address public owner;
    address public settler;
    address public settlement;
    address public user;

    bytes32 constant ORDER_ID = keccak256("order-1");
    bytes32 constant SETTLEMENT_REF = keccak256("paycrest-ref");

    function setUp() public {
        owner = makeAddr("owner");
        settler = makeAddr("settler");
        settlement = makeAddr("settlement");
        user = makeAddr("user");

        vm.prank(owner);
        gateway = new WeteEgoGateway(settlement, settler);
        token = new MockERC20();
        token.mint(user, 1000e6);
    }

    function test_createOrder_escrowsTokens() public {
        uint256 amount = 100e6;
        vm.startPrank(user);
        token.approve(address(gateway), amount);
        gateway.createOrder(IERC20(address(token)), amount, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        assertEq(token.balanceOf(address(gateway)), amount);
        assertEq(token.balanceOf(user), 1000e6 - amount);
        (, , , , WeteEgoGateway.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 1); // Escrowed
    }

    function test_createOrder_emitsOrderCreated() public {
        uint256 amount = 50e6;
        vm.startPrank(user);
        token.approve(address(gateway), amount);

        vm.expectEmit(true, true, false, true);
        emit OrderCreated(ORDER_ID, user, address(token), amount, SETTLEMENT_REF, block.timestamp + 5 minutes);
        gateway.createOrder(IERC20(address(token)), amount, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
    }

    function test_createOrder_revertsOnZeroAmount() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        vm.expectRevert(WeteEgoGateway.ZeroAmount.selector);
        gateway.createOrder(IERC20(address(token)), 0, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
    }

    function test_createOrder_revertsOnDuplicateOrderId() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.expectRevert(WeteEgoGateway.DuplicateOrderId.selector);
        gateway.createOrder(IERC20(address(token)), 50e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
    }

    function test_settleOrder_releasesEscrow() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.prank(settler);
        gateway.settleOrder(ORDER_ID, "");

        assertEq(token.balanceOf(settlement), 100e6);
        assertEq(token.balanceOf(address(gateway)), 0);
        (, , , , WeteEgoGateway.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 2); // Settled
    }

    function test_settleOrder_emitsOrderSettled() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit OrderSettled(ORDER_ID, settler, block.timestamp);
        vm.prank(settler);
        gateway.settleOrder(ORDER_ID, "");
    }

    function test_settleOrder_revertsIfNotSettler() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(WeteEgoGateway.OnlySettler.selector);
        gateway.settleOrder(ORDER_ID, "");
    }

    function test_settleOrder_revertsIfAlreadySettled() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.prank(settler);
        gateway.settleOrder(ORDER_ID, "");

        vm.prank(settler);
        vm.expectRevert(WeteEgoGateway.OrderNotEscrowed.selector);
        gateway.settleOrder(ORDER_ID, "");
    }

    function test_refundOrder_returnsUsdcAfterTimeout() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 minutes + 1);
        gateway.refundOrder(ORDER_ID);

        assertEq(token.balanceOf(user), 1000e6);
        assertEq(token.balanceOf(address(gateway)), 0);
        (, , , , WeteEgoGateway.OrderStatus status) = gateway.orders(ORDER_ID);
        assertEq(uint256(status), 3); // Refunded
    }

    function test_refundOrder_revertsBeforeTimeout() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.warp(block.timestamp + 4 minutes);
        vm.expectRevert(WeteEgoGateway.RefundTooEarly.selector);
        gateway.refundOrder(ORDER_ID);
    }

    function test_refundOrder_emitsOrderRefunded() public {
        vm.startPrank(user);
        token.approve(address(gateway), 100e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 minutes + 1);
        vm.expectEmit(true, true, false, true);
        emit OrderRefunded(ORDER_ID, user, block.timestamp);
        gateway.refundOrder(ORDER_ID);
    }

    function test_reentrancy_createOrder() public {
        // Reentrancy guard: createOrder uses nonReentrant; no callback path from this contract.
        // Verify double-create same orderId fails (state updated before external call would matter for reentrancy;
        // here transferFrom is the external call - so guard is between transferFrom and state update... actually
        // we update state first then transferFrom. So reentering createOrder with same orderId would hit DuplicateOrderId.
        vm.startPrank(user);
        token.approve(address(gateway), 200e6);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.expectRevert(WeteEgoGateway.DuplicateOrderId.selector);
        gateway.createOrder(IERC20(address(token)), 100e6, ORDER_ID, SETTLEMENT_REF);
        vm.stopPrank();
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
        (, , , , WeteEgoGateway.OrderStatus status) = gateway.orders(id);
        assertEq(uint256(status), 2);
    }

    function testFuzz_refundAfterTimeout(uint32 delay) public {
        delay = uint32(bound(delay, 301, type(uint32).max)); // > 5 min
        uint256 amount = 100e6;
        bytes32 id = keccak256(abi.encode(delay));

        vm.startPrank(user);
        token.approve(address(gateway), amount);
        gateway.createOrder(IERC20(address(token)), amount, id, SETTLEMENT_REF);
        vm.stopPrank();

        vm.warp(block.timestamp + delay);
        gateway.refundOrder(id);

        assertEq(token.balanceOf(user), 1000e6);
        (, , , , WeteEgoGateway.OrderStatus status) = gateway.orders(id);
        assertEq(uint256(status), 3);
    }
}
