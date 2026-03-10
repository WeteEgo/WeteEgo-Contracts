// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title WeteEgoRouter
 * @notice Routes USDC/ETH to a configurable settlement address (e.g. Paycrest gateway).
 *        Emits SwapForwarded for indexing and status tracking.
 */
contract WeteEgoRouter {
    using SafeERC20 for IERC20;

    address public immutable settlement;
    address public owner;

    event SwapForwarded(
        address indexed sender,
        address indexed token,
        uint256 amount,
        bytes32 settlementRef,
        uint256 timestamp
    );

    event SettlementAddressUpdated(address indexed previousSettlement, address indexed newSettlement);
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);

    error OnlyOwner();
    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _settlement) {
        if (_settlement == address(0)) revert ZeroAddress();
        settlement = _settlement;
        owner = msg.sender;
    }

    /**
     * @notice Forward USDC to settlement and emit event.
     * @param token ERC20 token (e.g. USDC).
     * @param amount Amount in token decimals.
     * @param settlementRef Optional reference for order/quote (e.g. keccak256(abi.encode(quoteId))).
     */
    function forwardERC20(
        IERC20 token,
        uint256 amount,
        bytes32 settlementRef
    ) external {
        if (address(token) == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, settlement, amount);
        emit SwapForwarded(msg.sender, address(token), amount, settlementRef, block.timestamp);
    }

    /**
     * @notice Forward native ETH to settlement and emit event.
     * @param settlementRef Optional reference for order/quote.
     */
    function forwardETH(bytes32 settlementRef) external payable {
        if (msg.value == 0) revert ZeroAmount();
        (bool ok,) = settlement.call{value: msg.value}("");
        if (!ok) revert TransferFailed();
        emit SwapForwarded(msg.sender, address(0), msg.value, settlementRef, block.timestamp);
    }

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address prev = owner;
        owner = newOwner;
        emit OwnerUpdated(prev, newOwner);
    }

    receive() external payable {}
}
