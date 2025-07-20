// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        // ensuring we have access to the ownable calls in contracts via owner
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        // giving vault access to mint and burn, due to role requirement we implemented
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1 ether}("");
        vm.stopPrank();
    }

    /**
     * @notice tests linear growth of rebase token, meaning an increase in a users balance should be the same from 0 hours to 1 hours, and 1 hours to 2 hours
     * @param amount fuzz testing: randomises amount variable, which is bounded (constricted) from 1e5 to max uint96 value
     */
    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        // low level transfer of eth to vault, elligble by receive function in vault code
        vault.deposit{value: amount}();

        // 2. check user rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance", startBalance);
        // should be the same as no time has accrued
        assertEq(startBalance, amount);

        // 3. warp time and check balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        assertGt(balanceAfterFirstWarp, startBalance);

        // 4. warp time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(user);
        assertGt(balanceAfterSecondWarp, balanceAfterFirstWarp);

        // to check linear growth, we must find the growth between each warp (which was the same time), as it will be the same if linear.
        // non-linear growth, by contrast, may have little interest accrued after 1 hour but then a lot by the 2nd hour.
        assertApproxEqAbs(balanceAfterFirstWarp - startBalance, balanceAfterSecondWarp - balanceAfterFirstWarp, 1);
        vm.stopPrank();
    }
}
