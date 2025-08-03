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

contract CrossChainTest is Test {
    uint256 sepoliaFork;
    uint256 arbSepolia;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    address owner = makeAddr("owner");
    Vault vault;
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    /**
     * @notice this set up first sets up the sepolia fork, switches to the arbitrum fork, and does the same
     */
    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepolia = vm.createFork("arb-sepolia");

        // deployment of ccip simulator, which mimicks the CCIP router, registries and cross-chain messaging behaviour
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // making it persistent means to keep the same ccipLocalSimulatorFork address even when we switch chains
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. deploy and configure on sepolia
        // becuase we are already on the sepolia chain, we get the network details for the current chain id
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
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

        // switching to setting up arbitrum
        configureTokenPool(
            arbSepolia, /* the fork we are switching to */
            RebaseTokenPool(address(arbSepoliaPool)), /* the associated with arbitrum */
            RebaseTokenPool(address(sepoliaPool)), /* once we are on arbitrum, the sepolia pool is the destination pool */
            IRebaseToken(address(sepoliaToken)), /* the token associated with the destination pool */
            sepoliaNetworkDetails /* the network details for the destination network */
        );
        vm.stopPrank();

        // 2. deploy and configure on arbitrum sepolia
        vm.selectFork(arbSepolia);
        vm.startPrank(owner);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
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
        configureTokenPool(
            sepoliaFork,
            RebaseTokenPool(address(sepoliaPool)),
            RebaseTokenPool(address(arbSepoliaPool)),
            IRebaseToken(address(arbSepoliaToken)),
            arbSepoliaNetworkDetails
        );
        vm.stopPrank();
    }

    // newer chainlink ccip removed the requirement to pass a chain to remove, and instead implemented the bool allowed on your new chain

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
}
