// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WeteEgoGatewayV2
 * @notice Phase 2 escrow: multisig admin, timelock for param changes, emergency pause, max order size.
 * - Param changes (settlement, settler, maxOrderAmount) only via TimelockController (24h delay).
 * - Emergency pause/unpause by PAUSER_ROLE (multisig).
 */
contract WeteEgoGatewayV2 is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant TIMELOCK_EXECUTOR_ROLE = keccak256("TIMELOCK_EXECUTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant REFUND_TIMEOUT = 5 minutes;

    address public settlementAddress;
    address public settler;
    uint256 public maxOrderAmount; // max USDC (6 decimals) per order; 0 = unlimited

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
    event MaxOrderAmountUpdated(uint256 previous, uint256 current);
    event EmergencyPaused(address indexed by);
    event EmergencyUnpaused(address indexed by);
    event ParameterExecuted(string indexed param, bytes value);

    error ZeroAddress();
    error ZeroAmount();
    error ExceedsMaxOrderAmount();
    error DuplicateOrderId();
    error OnlySettler();
    error OrderNotEscrowed();
    error RefundTooEarly();

    modifier onlySettler() {
        if (msg.sender != settler) revert OnlySettler();
        _;
    }

    constructor(
        address _settlementAddress,
        address _settler,
        uint256 _maxOrderAmount,
        address _timelockController,
        address _pauser
    ) {
        if (_settlementAddress == address(0)) revert ZeroAddress();
        if (_settler == address(0)) revert ZeroAddress();
        if (_timelockController == address(0)) revert ZeroAddress();
        if (_pauser == address(0)) revert ZeroAddress();

        settlementAddress = _settlementAddress;
        settler = _settler;
        maxOrderAmount = _maxOrderAmount;

        _grantRole(DEFAULT_ADMIN_ROLE, _pauser);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(TIMELOCK_EXECUTOR_ROLE, _timelockController);
    }

    function createOrder(
        IERC20 token,
        uint256 amount,
        bytes32 orderId,
        bytes32 settlementRef
    ) external nonReentrant whenNotPaused {
        if (address(token) == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (maxOrderAmount != 0 && amount > maxOrderAmount) revert ExceedsMaxOrderAmount();
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

    function settleOrder(bytes32 orderId, bytes calldata /* proof */) external onlySettler nonReentrant {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Escrowed) revert OrderNotEscrowed();

        o.status = OrderStatus.Settled;
        IERC20(o.token).safeTransfer(settlementAddress, o.amount);
        emit OrderSettled(orderId, msg.sender, block.timestamp);
    }

    function refundOrder(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Escrowed) revert OrderNotEscrowed();
        if (block.timestamp < o.expiresAt) revert RefundTooEarly();

        o.status = OrderStatus.Refunded;
        IERC20(o.token).safeTransfer(o.sender, o.amount);
        emit OrderRefunded(orderId, o.sender, block.timestamp);
    }

    // --- Timelock-only (param changes after 24h delay) ---

    function setSettlementAddress(address _settlementAddress) external onlyRole(TIMELOCK_EXECUTOR_ROLE) {
        if (_settlementAddress == address(0)) revert ZeroAddress();
        address prev = settlementAddress;
        settlementAddress = _settlementAddress;
        emit SettlementAddressUpdated(prev, _settlementAddress);
        emit ParameterExecuted("settlementAddress", abi.encode(_settlementAddress));
    }

    function setSettler(address _settler) external onlyRole(TIMELOCK_EXECUTOR_ROLE) {
        if (_settler == address(0)) revert ZeroAddress();
        address prev = settler;
        settler = _settler;
        emit SettlerUpdated(prev, _settler);
        emit ParameterExecuted("settler", abi.encode(_settler));
    }

    function setMaxOrderAmount(uint256 _maxOrderAmount) external onlyRole(TIMELOCK_EXECUTOR_ROLE) {
        uint256 prev = maxOrderAmount;
        maxOrderAmount = _maxOrderAmount;
        emit MaxOrderAmountUpdated(prev, _maxOrderAmount);
        emit ParameterExecuted("maxOrderAmount", abi.encode(_maxOrderAmount));
    }

    // --- Emergency pause (multisig, immediate) ---

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit EmergencyPaused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }
}
