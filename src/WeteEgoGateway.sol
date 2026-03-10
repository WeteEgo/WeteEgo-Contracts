// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title WeteEgoGateway
 * @notice Phase 1 escrow: user deposits USDC; contract holds until settlement proof or 5-min timeout refund.
 */
contract WeteEgoGateway is ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    uint256 public constant REFUND_TIMEOUT = 5 minutes;

    address public settlementAddress;
    address public settler;

    enum OrderStatus {
        None,
        Escrowed,
        Settled,
        Refunded
    }

    struct Order {
        address sender;
        address token;
        uint256 amount;
        uint256 expiresAt;
        OrderStatus status;
    }

    mapping(bytes32 orderId => Order) public orders;

    event OrderCreated(
        bytes32 indexed orderId,
        address indexed sender,
        address token,
        uint256 amount,
        bytes32 settlementRef,
        uint256 expiresAt
    );
    event OrderSettled(bytes32 indexed orderId, address indexed settler, uint256 settledAt);
    event OrderRefunded(bytes32 indexed orderId, address indexed refundedTo, uint256 refundedAt);
    event SettlementAddressUpdated(address indexed previous, address indexed current);
    event SettlerUpdated(address indexed previous, address indexed current);

    error ZeroAddress();
    error ZeroAmount();
    error DuplicateOrderId();
    error OnlySettler();
    error OrderNotEscrowed();
    error OrderAlreadySettled();
    error OrderAlreadyRefunded();
    error RefundTooEarly();

    modifier onlySettler() {
        if (msg.sender != settler) revert OnlySettler();
        _;
    }

    constructor(address _settlementAddress, address _settler) Ownable(msg.sender) {
        if (_settlementAddress == address(0)) revert ZeroAddress();
        if (_settler == address(0)) revert ZeroAddress();
        settlementAddress = _settlementAddress;
        settler = _settler;
    }

    /**
     * @notice Create an order: pull token from sender and hold in escrow.
     * @param token ERC20 (e.g. USDC).
     * @param amount Amount in token decimals.
     * @param orderId Unique id from Order Service; must not reuse.
     * @param settlementRef Correlation ref for Paycrest/backend.
     */
    function createOrder(
        IERC20 token,
        uint256 amount,
        bytes32 orderId,
        bytes32 settlementRef
    ) external nonReentrant {
        if (address(token) == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (orders[orderId].status != OrderStatus.None) revert DuplicateOrderId();

        uint256 expiresAt = block.timestamp + REFUND_TIMEOUT;
        orders[orderId] = Order({
            sender: msg.sender,
            token: address(token),
            amount: amount,
            expiresAt: expiresAt,
            status: OrderStatus.Escrowed
        });

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit OrderCreated(orderId, msg.sender, address(token), amount, settlementRef, expiresAt);
    }

    /**
     * @notice Settle order: release escrowed tokens to settlement address. Callable only by settler.
     */
    function settleOrder(bytes32 orderId, bytes calldata /* proof */) external onlySettler nonReentrant {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Escrowed) revert OrderNotEscrowed();

        o.status = OrderStatus.Settled;
        IERC20(o.token).safeTransfer(settlementAddress, o.amount);
        emit OrderSettled(orderId, msg.sender, block.timestamp);
    }

    /**
     * @notice Refund order after timeout. Callable by anyone.
     */
    function refundOrder(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Escrowed) revert OrderNotEscrowed();
        if (block.timestamp < o.expiresAt) revert RefundTooEarly();

        o.status = OrderStatus.Refunded;
        address to = o.sender;
        IERC20(o.token).safeTransfer(to, o.amount);
        emit OrderRefunded(orderId, to, block.timestamp);
    }

    function setSettlementAddress(address _settlementAddress) external onlyOwner {
        if (_settlementAddress == address(0)) revert ZeroAddress();
        address prev = settlementAddress;
        settlementAddress = _settlementAddress;
        emit SettlementAddressUpdated(prev, _settlementAddress);
    }

    function setSettler(address _settler) external onlyOwner {
        if (_settler == address(0)) revert ZeroAddress();
        address prev = settler;
        settler = _settler;
        emit SettlerUpdated(prev, _settler);
    }
}
