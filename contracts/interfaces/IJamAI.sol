// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IJammer} from "./IJammer.sol";

interface IJamAI {

    event Trade(
        address trader,
        uint256 aiAgentId,
        bool isBuy,
        uint256 amount,
        uint256 ethAmount,
        uint256 protocolFee,
        uint256 supply
    );

    struct TokenInfo {
        string name;
        string symbol;
        bytes32 salt;
    }

    error TradeNotEnabled();
    error PoolLaunched();
    error InvalidMessage();
    error InvalidSignature();
    error TradeAlreadyEnabled();
    error InsufficientPayment();
    error TransferFailed();
    error InsufficientTicketsToSell();
    error PoolAlreadyCreated();
    error InsufficientTicketsForPool();
    error InvalidTokenInfo();
    error SellNotEnabled();
    error LastTicketNotSellable();

    function jammer() external returns (IJammer);

    function ticketsSupply(uint256 aiAgentId) external view returns (uint256);
    function ticketsBalance(uint256 aiAgentId, address holder) external view returns (uint256);

    function getBuyPrice(uint256 aiAgentId, uint256 amount) external view returns (uint256);
    function getSellPrice(uint256 aiAgentId, uint256 amount) external view returns (uint256);

    function getBuyPriceWithFee(uint256 aiAgentId, uint256 amount) external view returns (uint256);
    function getSellPriceWithFee(uint256 aiAgentId, uint256 amount) external view returns (uint256);

    function startTrading(bytes calldata message, bytes calldata signature) external payable;
    function buyTickets(uint256 aiAgentId, uint256 amount) external payable;
    function sellTickets(uint256 aiAgentId, uint256 amount) external;
}
