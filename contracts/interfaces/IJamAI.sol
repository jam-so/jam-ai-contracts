// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IJammer} from "./IJammer.sol";

interface IJamAI {
    function jammer() external returns (IJammer);

    function sharesSupply(uint256 aiAgentID) external view returns (uint256);
    function sharesBalance(uint256 aiAgentID, address holder) external view returns (uint256);

    function getBuyPrice(uint256 aiAgentID, uint256 amount) external view returns (uint256);
    function getSellPrice(uint256 aiAgentID, uint256 amount) external view returns (uint256);

    function getBuyPriceWithFee(uint256 aiAgentID, uint256 amount) external view returns (uint256);
    function getSellPriceWithFee(uint256 aiAgentID, uint256 amount) external view returns (uint256);

    function enableTrade(bytes calldata message, bytes calldata signature) external payable;
    function buyShares(uint256 aiAgentID, uint256 amount) external payable;
    function sellShares(uint256 aiAgentID, uint256 amount) external payable;
}
