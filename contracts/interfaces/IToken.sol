// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IToken is IERC20 {
    function aiAgentID() external view returns (uint256);
    function claimableAmount() external view returns (uint256);
    function claim() external;

    function initialize() external;
}
