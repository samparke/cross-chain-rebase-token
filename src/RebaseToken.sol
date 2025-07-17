// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RebaseToken is ERC20 {
    // ERROR
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    // STATE VARIABLES
    uint256 private s_interestRate = 5e10;

    // EVENTS
    event ChangedInterestRate(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    /*
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
}
