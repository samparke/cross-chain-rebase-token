// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    Vault vault;
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;
    uint256 public constant SEND_VALUE = 1e5;

    /**
     * @notice this set up first sets up the sepolia fork, switches to the arbitrum fork, and does the same
     */
    function setUp() public {
        address[] memory allowList = new address[](0);
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // deployment of ccip simulator, which mimicks the CCIP router, registries and cross-chain messaging behaviour
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // making it persistent means to keep the same ccipLocalSimulatorFork address even when we switch chains
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. deploy and configure on sepolia
        // becuase we are already on the sepolia chain, we get the network details for the current chain id
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.makePersistent(sepoliaNetworkDetails.rmnProxyAddress);
        vm.makePersistent(sepoliaNetworkDetails.routerAddress);

        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            allowList,
            // retrieves rmnProxyAddress and routerAddress from the sepoliaNetworkDetails
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));

        // these functions tells CCIP on-chain registry about our sepolia token. Like a receptionist
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        // accepts admin role for my token
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        // this acceptance of admin role then allows the token to set an associated pool
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );
        vm.stopPrank();
        // switching to setting up arbitrum

        // 2. deploy and configure on arbitrum sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.makePersistent(arbSepoliaNetworkDetails.rmnProxyAddress);
        vm.makePersistent(arbSepoliaNetworkDetails.routerAddress);

        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            allowList,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(vault));
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();
    }

    /**
     * @notice this function configures the fork that you are switching to. Unlike older version, where you had to remove a chain first, newer versions
     * just requires you to add a chain, and clarify whether it is allowed via bool allowed
     * @param fork the fork we are switching to
     * @param localPool the local pool we call the applyChainUpdates to
     * @param remotePool the remote pool of the destination fork
     * @param remoteToken the remote token of the destination fork
     * @param remoteNetworkDetails the network details of the destination fork
     */
    function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(address(remotePool)),
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        localPool.applyChainUpdates(chainsToAdd);
        vm.stopPrank();
    }

    /**
     * @notice this function bridges the tokens
     * @param amountToBridge the amount of local tokens we want to bridge
     * @param localFork the fork we are sending from
     * @param remoteFork the destination fork
     * @param localNetworkDetails the details of our current fork, such as the router address assigned to that fork
     * @param remoteNetworkDetails the details of the destination fork, such as the chain selector on that fork
     * @param localToken the local token we are sending, such as Sepolia. This will be the token being locked or burned
     * @param remoteToken the token we are receiving, such as Arbitrum Sepolia. This will be the token being released or minted
     */
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        // we declare the token amounts we want to send, specifying the specific token (localToken) and the amount (amountToBridge)
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        // we create the message (as requested by EVMAnyMessage function)
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: ""
        });
        // the fee has to be calculated after the message is created
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        // as this is a simulation, we then request funding (in LINK) from the ccip faucet
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        vm.prank(user);
        // from the user, we grant the router address access to our link we just gained (for the fee amount)
        // this allows the ccip router to take our fee
        IERC20((localNetworkDetails.linkAddress)).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(user);
        // we then allow the router to take our local token in the amountToBridge
        // this allows the ccip router to take our tokens are bridge them
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(user);
        vm.prank(user);
        // from the router client, we are sending the remote network the message (which contains our tokens to send etc)
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        // we are only switching forks here to check the user balance before routing message
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);

        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(remoteUserInterestRate, localUserInterestRate);
    }

    function testBridgeAllTokens() public {
        configureTokenPool(
            sepoliaFork,
            RebaseTokenPool(address(sepoliaPool)),
            RebaseTokenPool(address(arbSepoliaPool)),
            IRebaseToken(address(arbSepoliaToken)),
            arbSepoliaNetworkDetails
        );

        configureTokenPool(
            arbSepoliaFork, /* the fork we are switching to */
            RebaseTokenPool(address(arbSepoliaPool)), /* the associated with arbitrum */
            RebaseTokenPool(address(sepoliaPool)), /* once we are on arbitrum, the sepolia pool is the destination pool */
            IRebaseToken(address(sepoliaToken)), /* the token associated with the destination pool */
            sepoliaNetworkDetails /* the network details for the destination network */
        );

        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // after depositing eth, the vault mints sepolia tokens
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
    }
}
