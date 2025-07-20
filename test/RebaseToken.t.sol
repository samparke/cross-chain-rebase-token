// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;
    // in a real world scenario, funds are unlikely to come from the owner (which is one of the purposes of the owner in these tests)
    // instead, users funds are typically reinvested into other money-making protocols, which then funds the original protocol
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        // ensuring we have access to the ownable calls in contracts via owner
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        // giving vault access to mint and burn, due to role requirement we implemented
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        // side note: low level calls return a bool (indicating the success of the call) and bytes data
        // (bool success,) means we only extract the success of the call
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
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

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // when we call deposit, it mints the rebaseToken in the msg.value amount we sent to the function.
        // the user should therefore have rebaseToken in amount quantitiy
        assertEq(rebaseToken.balanceOf(user), amount);

        // 2. redeem
        // type(uint256).max is checked for in our burn function, which redeem() uses
        // sets the amount to our entire balance
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // randomise time between 1000 seconds and a longer time
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        // 1. deposit
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // 2. warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        // 2b. add the rewards to the vault
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);

        // 3. redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);
        uint256 ethBalance = address(user).balance;
        // because we mint rebase tokens in the same quantity as we deposited,
        // the eth balance after redeeming and rebase token balance before redeeming should be the same
        assertEq(ethBalance, balanceAfterSomeTime);
        // as time has passed, the final eth balance after redeeming our rebase tokens should be greater than the amount of eth we initially deposited
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        // user should have balance because we minted with the address
        assertEq(userBalance, amount);
        // user 2 should have no rebase as they did not deposit collateral
        assertEq(user2Balance, 0);

        // owner reduces interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 2. transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, user2Balance + amountToSend);

        // 3. check user 2 has inherited interest rate from user, remember everytime a user without previous interaction interacts, they inherit the other users interest rate
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
    }
}
