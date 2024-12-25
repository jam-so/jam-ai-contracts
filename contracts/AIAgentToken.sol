// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IAIAgentToken} from "./interfaces/IAIAgentToken.sol";
import {IJamAI} from "./interfaces/IJamAI.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AIAgentToken is ERC20, IAIAgentToken {

    // Holder => IsClaimed
    mapping(address => bool) public holderClaims;

    IJamAI private immutable _jamAI;
    uint256 private immutable _aiAgentId;

    bool private _initialized;
    uint256 private _totalClaimable;

    uint256 public immutable TOTAL_SUPPLY = 10**29;

     constructor(
        string memory name_,
        string memory symbol_,
        IJamAI jamAI_,
        uint256 aiAgentId_
    ) ERC20(name_, symbol_) {
        require(address(jamAI_) != address(0), "invalid jamAI address");
        require(aiAgentId_ != 0, "invalid aiAgentId");

        _jamAI = jamAI_;
        _aiAgentId = aiAgentId_;
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    function jamAI() external view returns (address) {
        return address(_jamAI);
    }

    function aiAgentId() public view returns (uint256) {
        return _aiAgentId;
    }

    function totalClaimable() external view returns (uint256) {
        return _totalClaimable;
    }

    function claimable(address account) external view returns (uint256) {
        return _claimable(account);
    }

    function claim() external {
        uint256 amount = _claimable(msg.sender);
        if (holderClaims[msg.sender] || amount == 0)
            revert NoClaimableAmount();

        holderClaims[msg.sender] = true;
        ERC20(address(this)).transfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    function _claimable(address account) internal view returns (uint256) {
        if (holderClaims[account])
            return 0;

        uint256 supply = _jamAI.ticketsSupply(_aiAgentId);
        uint256 balance = _jamAI.ticketsBalance(_aiAgentId, account);

        uint256 amount = _totalClaimable * balance / supply;

        // If this is the last claim.
        if (balanceOf(address(this))-amount <= 1) {
            amount = balanceOf(address(this));
        }

        return amount;
    }

    function initialize() external {
        if (msg.sender != address(_jamAI.jammer()))
            revert NotAuthorized();
        if (_initialized)
            revert AlreadyInitialized();

        _initialized = true;
        _totalClaimable = balanceOf(address(this));
    }
}
