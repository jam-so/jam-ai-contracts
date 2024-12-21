// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {IJamAI} from "./interfaces/IJamAI.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {

    // holder => isClaimed
    mapping(address => bool) public holderClaims;

    IJamAI private immutable _jamAI;
    uint256 private immutable _aiAgentID;

    bool private _initialized;
    uint256 private _initialAmount;

    error AlreadyInitialized();
    error NoClaimableAmount();
    error NotAuthorized();

     constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        IJamAI jamAI_,
        uint256 aiAgentID_
    ) ERC20(name_, symbol_) {
        require(address(jamAI_) != address(0), "invalid jamAI address");
        require(aiAgentID_ != 0, "invalid aiAgentID");

        _jamAI = jamAI_;
        _aiAgentID = aiAgentID_;
        _mint(msg.sender, maxSupply_);
    }

    function jamAI() external view returns (address) {
        return address(_jamAI);
    }

    function aiAgentID() public view returns (uint256) {
        return _aiAgentID;
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
    }

    function _claimableAmount() internal view returns (uint256) {
        if (holderClaims[msg.sender])
            return 0;

        uint256 supply = _jamAI.sharesSupply(_aiAgentID);
        uint256 balance = _jamAI.sharesBalance(_aiAgentID, msg.sender);

        uint256 claimable = _initialAmount * balance / supply;

        // If this is the last claim.
        if (balanceOf(address(this))-claimable <= 1) {
            claimable = balanceOf(address(this));
        }

        return claimable;
    }

    function initialize() external {
        if (msg.sender != address(_jamAI.jammer())) revert NotAuthorized();
        if (_initialized) revert AlreadyInitialized();

        _initialized = true;
        _initialAmount = balanceOf(address(this));
    }
}
