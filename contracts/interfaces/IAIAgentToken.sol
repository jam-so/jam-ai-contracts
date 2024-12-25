// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAIAgentToken is IERC20 {
    event Claimed(address indexed to, uint256 amount);

    error AlreadyInitialized();
    error NoClaimableAmount();
    error NotAuthorized();

    function aiAgentId() external view returns (uint256);
    function claimable(address account) external view returns (uint256);
    function claim() external;

    function initialize() external;
}
