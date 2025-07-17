// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RebaseToken is ERC20 {
    // ERROR
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    // STATE VARIABLES
    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // EVENTS
    event ChangedInterestRate(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    /**
     * @notice sets the interest rate for the contract
     * @param _newInterestRate is the new interest rate
     * @dev The interest rate can only decrease. Hence, revert if _newInterestRate > s_interestRate
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit ChangedInterestRate(_newInterestRate);
    }

    /**
     * @notice mint the user tokens when they deposit into the vault
     * @param _to The user to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        // before we set the users new interest rate, we want to mint according to their current interest rate
        // our protocol works so that whenever a user deposits, they get a new interest rate, even if this is less than their previous interest rate
        _mintAccruedInterest(_to);
        // sets the users interest rate to the current global interest rate
        s_userInterestRate[_to] = s_interestRate;
        // inherited from ERC20 contract from openzeppelin
        _mint(_to, _amount);
    }

    /**
     * @notice calculate the interest that has accumulated since the last update
     * @param _user the user to calculate interest accumulated
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find current balance of rebase tokens (principle balance)
        // (2) calculate current balance, including any interest (balanceOf)
        // (2-1) calculate the number of tokens that need to be minted to user
        // call _mint to mint the tokens to the user
        // set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    /**
     * @notice calculate the balance for user including the interest that has accumulated since the last update
     * (principle interes)t + some interest that has accrued
     * @param _user the user whose balance we are retreiving
     * @return The balance of the user, including the interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // 'super.' avoids loop. Without it, it would call this function again, and again
        // since we want to call the ERC20 balanceOf, using super searches for this function in inherited contracts, and uses it
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256) {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth
        // 1. calculate time since last updated
        // 2. calculate the amount of linear growth

        // (principle amount) + principle amount + user interest rate + time elapsed
        // example:
        // deposit: 10 tokens
        // interest rate: 0.5 tokens per second
        // time elapsed: 2 seconds
        // 10 + (10 * 0.5 * 2)
    }

    // GETTER FUNCTIONS
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
