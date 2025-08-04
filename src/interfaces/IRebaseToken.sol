// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice This interface essentially acts as a middleman between the RebaseToken and the Vault.
 * like the IERC20 interface, it acts as a shell for the rebase token.
 *
 * How it works:
 * When the vault is initialised, the rebase token is wrapped in the interface.
 * The interface only contains the core functions which need to be called, such as mint and burn
 * It does not contain any other logic, such as calculation of interest. This is done via the RebaseToken.sol
 * The vault doesn't need access to all this other functionality, it only need access to mint and burn via the interface,
 * which then links to the rebase token containing this logic.
 * It's similar to using internal functions in a contract (in terms of modularity).
 */
interface IRebaseToken {
    function mint(address _to, uint256 _amount, uint256 _interestRate) external;
    function burn(address _from, uint256 _amount) external;
    function balanceOf(address user) external view returns (uint256);
    function getUserInterestRate(address user) external view returns (uint256);
    function getInterestRateForContract() external view returns (uint256);
    function grantMintAndBurnRole(address _account) external;
}
