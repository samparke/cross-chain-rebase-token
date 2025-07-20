// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "openzeppelin/contracts/access/AccessControl.sol";

contract RebaseToken is ERC20, Ownable, AccessControl {
    // ERROR
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    // STATE VARIABLES

    // instead of 5e10, we use this for more accurate precision (previous truncation)
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // this is 1 in 18 decimal precision
    uint256 private constant PRECISION_FACTOR = 1e27; // 10^27
    // hashes "MINT_AND_BURN_ROLE"
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    // EVENTS
    event ChangedInterestRate(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice sets the interest rate for the contract
     * @param _newInterestRate is the new interest rate
     * @dev The interest rate can only decrease. Hence, revert if _newInterestRate > s_interestRate
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
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
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // before we set the users new interest rate, we want to mint according to their current interest rate
        // our protocol works so that whenever a user deposits, they get a new interest rate, even if this is less than their previous interest rate
        _mintAccruedInterest(_to);
        // sets the users interest rate to the current global interest rate
        s_userInterestRate[_to] = s_interestRate;
        // inherited from ERC20 contract from openzeppelin
        _mint(_to, _amount);
    }

    /**
     * @notice burn the user tokens when they withdraw from the vault (if you are taking out your eth, we need to burn the rebase token you received)
     * @param _from the user to burn the tokens from
     * @param _amount the amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice mint the accrued interest to the user since the last time they interacted with the protocol (eg. burn, mint, transfer)
     * @param _user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find current balance of rebase tokens (principle balance)
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate current balance, including any interest (balanceOf)
        uint256 currentBalance = balanceOf(_user);
        // (2-1) calculate the number of tokens that need to be minted to user
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
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
        // also, because we are mutiplying precision factor by another precision factor, we need to divide to get it back to the normal precision factor
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice transfer tokens from user to another
     * @param _recipient the user to transfer tokens to
     * @param _amount the amount of tokens to transfer
     * @return true if transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        // if they are sending their entire balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        // if recipient has not used the protocol before, we set their interest rate to that of the msg.sender
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice transfer tokens from one user to another
     * @param _sender the user to transfer tokens from
     * @param _recipient the user to recieve tokens
     * @param _amount the amount of tokens to transfer
     * @return true if transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        // if they are sending their entire balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        // if recipient has not used the protocol before, we set their interest rate to that of the msg.sender
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice calculate the interest that has accumulated since the last update
     * @param _user the user to calculate interest accumulated for
     * @return linearInterest the interest that has accumulated since the last update
     *
     * Why use internal functions?
     * Internal functions are used for 'under-the-hood' calculations
     * It seperates internal logic, such as the calculation of interest, from retreving the balanceOf a user
     * Aside from better readability (not having incredibly long functions doing multiple things), its more modular.
     * It can be easily called in seperate functions, without having to type it all out again.
     * It' similar to using modifiers, such as creating onlyOwner, instead of repeatedly typing out "(if msg.sender!=owner...)"
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth
        // 1. calculate time since last updated
        // 2. calculate the amount of linear growth

        // principle amount (1 + (user interest rate * time elapsed)
        // example:
        // deposit: 10 tokens
        // interest rate: 0.5 tokens per second
        // time elapsed: 2 seconds
        // 10 + (10 * 0.5 * 2)
        // the principle amount is the number of tokens that have actually been minted to them
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        // s_userInterestRate is in 18 decimal precision aleady, so we need to use PRECISION_FACTOR (1e18), instead of just 1
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    // GETTER FUNCTIONS
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice get principle balance of a user. This is the number of tokens that have currently been minted to the user not including any interest that has accrued since the last time the user has interested with the protocol.
     * @param _user user to get principle balance for
     * @return returns users principle balance
     */
    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice get interest rate that is currently set for the contract. Any future depositors will recieve this interest
     * @return contract interest rate
     */
    function getInterestRateForContract() external view returns (uint256) {
        return s_interestRate;
    }
}
