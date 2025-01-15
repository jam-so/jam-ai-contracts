// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IJammer} from "./IJammer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IJamAI {

    event Trade(
        address trader,
        uint256 aiAgentId,
        bool isBuy,
        uint256 amount,
        uint256 price,
        uint256 protocolFee,
        uint256 supply
    );

    event SetFeeTo(address feeTo);
    event SetJammer(address jammer);
    event SetTradeApprover(address tradeApprover);
    event SetBuyFeeRate(uint256 buyFeeRate);
    event SetSellFeeRate(uint256 sellFeeRate);
    event SetThreshold(uint256 threshold);
    event SetSellEnabled(bool enabled);
    event UpdateTokenInfo(uint256 aiAgentId, string name, string symbol, bytes32 salt);

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
    error InsufficientTicketsToSell();
    error PoolAlreadyCreated();
    error InsufficientTicketsForPool();
    error InvalidTokenInfo();
    error SellNotEnabled();
    error LastTicketNotSellable();

    function jam() external view returns (IERC20);
    function jammer() external returns (IJammer);

    function ticketsSupply(uint256 aiAgentId) external view returns (uint256);
    function ticketsBalance(uint256 aiAgentId, address holder) external view returns (uint256);

    function getBuyPrice(uint256 aiAgentId, uint256 amount) external view returns (uint256);
    function getSellPrice(uint256 aiAgentId, uint256 amount) external view returns (uint256);

    function getBuyPriceWithFee(uint256 aiAgentId, uint256 amount) external view returns (uint256);
    function getSellPriceWithFee(uint256 aiAgentId, uint256 amount) external view returns (uint256);

    function startTrading(bytes calldata message, bytes calldata signature) external;
    function buyTickets(uint256 aiAgentId, uint256 amount) external;
    function sellTickets(uint256 aiAgentId, uint256 amount) external;
}
