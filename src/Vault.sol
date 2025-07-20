// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract Vault {
    //  ERRORS
    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;
    // we need to pass the token address to the constrcutor to mint and burn
    // create deposit function that mints tokens to user equal to the amount eth user sent
    // redeem function that burns tokens from the user and sends the user eth
    // create a way to add rewards to the vault

    event Deposit(address indexed _user, uint256 _amount);
    event Redeem(address indexed _user, uint256 _amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    // receive function to receive rewards to the vault
    receive() external payable {}

    /**
     * @notice allows users to deposit eth into the vault and mint rebase tokens in return
     */
    function deposit() external payable {
        // we need to use the amount of eth the user has sent to mint tokens to use
        i_rebaseToken.mint(msg.sender, msg.value);
        // emit event
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice allows users to redeem eth for rebase tokens
     * @param _amount amount of eth to redeem
     */
    function redeem(uint256 _amount) external {
        // 1. burn tokens from user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. send users eth using low-level call
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice address of the rebase token
     * @return the address of the rebase token
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
