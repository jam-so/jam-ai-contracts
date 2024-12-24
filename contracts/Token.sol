// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IToken} from "./interfaces/IToken.sol";
import {IJamAI} from "./interfaces/IJamAI.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20, IToken {

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

    function claimableAmount() external view returns (uint256) {
        return _claimableAmount();
    }

    function claim() external {
        uint256 claimable = _claimableAmount();
        if (holderClaims[msg.sender] || claimable == 0)
            revert NoClaimableAmount();

        holderClaims[msg.sender] = true;
        transfer(msg.sender, claimable);

        emit Claimed(msg.sender, claimable);
    }

    function _claimableAmount() internal view returns (uint256) {
        if (holderClaims[msg.sender])
            return 0;

        uint256 supply = _jamAI.ticketsSupply(_aiAgentId);
        uint256 balance = _jamAI.ticketsBalance(_aiAgentId, msg.sender);

        uint256 claimable = _totalClaimable * balance / supply;

        // If this is the last claim.
        if (balanceOf(address(this))-claimable <= 1) {
            claimable = balanceOf(address(this));
        }

        return claimable;
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
