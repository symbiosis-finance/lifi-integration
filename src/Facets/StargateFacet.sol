// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ILiFi } from "../Interfaces/ILiFi.sol";
import { IStargateRouter, IFactory, IPool } from "../Interfaces/IStargateRouter.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { LibDiamond } from "../Libraries/LibDiamond.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { InvalidAmount, InformationMismatch, InvalidConfig, InvalidCaller, TokenAddressIsZero, AlreadyInitialized, NotInitialized } from "../Errors/GenericErrors.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { LibMappings } from "../Libraries/LibMappings.sol";
import { Validatable } from "../Helpers/Validatable.sol";

/// @title Stargate Facet
/// @author Li.Finance (https://li.finance)
/// @notice Provides functionality for bridging through Stargate
contract StargateFacet is ILiFi, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    /// @notice The contract address of the stargate router on the source chain.
    IStargateRouter private immutable router;

    /// Types ///

    struct PoolIdConfig {
        address token;
        uint16 poolId;
    }

    struct ChainIdConfig {
        uint256 chainId;
        uint16 layerZeroChainId;
    }

    /// @param dstPoolId Dest pool id.
    /// @param minAmountLD The min qty you would accept on the destination.
    /// @param dstGasForCall Additional gas fee for extral call on the destination.
    /// @param refundAddress Refund adddress. Extra gas (if any) is returned to this address
    /// @param lzFee Estimated message fee.
    /// @param callTo The address to send the tokens to on the destination.
    /// @param callData Additional payload.
    struct StargateData {
        uint256 dstPoolId;
        uint256 minAmountLD;
        uint256 dstGasForCall;
        uint256 lzFee;
        address payable refundAddress;
        bytes callTo;
        bytes callData;
    }

    /// Errors ///

    error UnknownStargatePool();
    error UnknownLayerZeroChain();
    error InvalidStargateRouter();

    /// Events ///

    event StargateInitialized(PoolIdConfig[] poolIdConfigs, ChainIdConfig[] chainIdConfigs);
    event StargatePoolIdSet(address indexed token, uint256 poolId);
    event LayerZeroChainIdSet(uint256 indexed chainId, uint16 layerZeroChainId);

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _router The contract address of the stargate router on the source chain.
    constructor(IStargateRouter _router) {
        router = _router;
    }

    /// Init ///

    /// @notice Initialize local variables for the Stargate Facet
    /// @param poolIdConfigs Pool Id configuration data
    /// @param chainIdConfigs Chain Id configuration data
    function initStargate(PoolIdConfig[] calldata poolIdConfigs, ChainIdConfig[] calldata chainIdConfigs) external {
        LibDiamond.enforceIsContractOwner();

        LibMappings.StargateMappings storage sm = LibMappings.getStargateMappings();

        if (sm.initialized) {
            revert AlreadyInitialized();
        }

        for (uint256 i = 0; i < poolIdConfigs.length; i++) {
            if (poolIdConfigs[i].token == address(0)) {
                revert InvalidConfig();
            }
            sm.stargatePoolId[poolIdConfigs[i].token] = poolIdConfigs[i].poolId;
        }

        for (uint256 i = 0; i < chainIdConfigs.length; i++) {
            sm.layerZeroChainId[chainIdConfigs[i].chainId] = chainIdConfigs[i].layerZeroChainId;
        }

        sm.initialized = true;

        emit StargateInitialized(poolIdConfigs, chainIdConfigs);
    }

    /// External Methods ///

    /// @notice Bridges tokens via Stargate Bridge
    /// @param _bridgeData Data used purely for tracking and analytics
    /// @param _stargateData Data specific to Stargate Bridge
    function startBridgeTokensViaStargate(ILiFi.BridgeData memory _bridgeData, StargateData calldata _stargateData)
        external
        payable
        refundExcessNative(payable(msg.sender))                     //! returns remaining gas to sender after function
        doesNotContainSourceSwaps(_bridgeData)                      //! makes sure that BridgeData does not contains swap info
        validateBridgeData(_bridgeData)                             //! receiver != address(0) && minAmount != 0
        noNativeAsset(_bridgeData)                                  //! prevents usage of native asset as sendingAssetId
        nonReentrant
    {
        validateDestinationCallFlag(_bridgeData, _stargateData);
        LibAsset.depositAsset(_bridgeData.sendingAssetId, _bridgeData.minAmount);
        _startBridge(_bridgeData, _stargateData);
    }

    /// @notice Performs a swap before bridging via Stargate Bridge
    /// @param _bridgeData Data used purely for tracking and analytics
    /// @param _swapData An array of swap related data for performing swaps before bridging
    /// @param _stargateData Data specific to Stargate Bridge
    function swapAndStartBridgeTokensViaStargate(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        StargateData calldata _stargateData
    )
        external
        payable
        refundExcessNative(payable(msg.sender))                     //! returns remaining gas to sender after function
        containsSourceSwaps(_bridgeData)                            //! makes sure that BridgeData contains swap info
        validateBridgeData(_bridgeData)                             //! receiver != address(0) && minAmount != 0
        noNativeAsset(_bridgeData)                                  //! prevents usage of native asset as sendingAssetId
        nonReentrant
    {
        //! make sure that data for message call was provided if tx is flagged for destination call   
        validateDestinationCallFlag(_bridgeData, _stargateData);
        
        //! get deposit from sender and executeswap
        //! bridging fee is paid in native tokens on source chain
        //TODO - Is getting paid in native asset specific for starlink only or common practice?
        //TODO - Are we using the amountOut of the swaps as minAmountOut for the bridging since the bridging 
        //TODO   fee is already paid and we expect a 1:1 bridging?
        _bridgeData.minAmount = _depositAndSwap(
            _bridgeData.transactionId,
            _bridgeData.minAmount,
            _swapData,
            payable(msg.sender),
            _stargateData.lzFee
        );

        //! bridge assets using stargate bridge
        _startBridge(_bridgeData, _stargateData);
    }

    function quoteLayerZeroFee(uint256 _destinationChainId, StargateData calldata _stargateData)
        external
        view
        returns (uint256, uint256)
    {
        return
            router.quoteLayerZeroFee(
                getLayerZeroChainId(_destinationChainId),
                1, // TYPE_SWAP_REMOTE on Bridge
                _stargateData.callTo,
                _stargateData.callData,
                IStargateRouter.lzTxObj(_stargateData.dstGasForCall, 0, toBytes(msg.sender))
            );
    }

    /// Private Methods ///

    /// @dev Contains the business logic for the bridge via Stargate Bridge
    /// @param _bridgeData Data used purely for tracking and analytics
    /// @param _stargateData Data specific to Stargate Bridge
    function _startBridge(ILiFi.BridgeData memory _bridgeData, StargateData calldata _stargateData)
        private
        noNativeAsset(_bridgeData)    //! prevents usage of native asset (address(0) as sendingAssetId
    {
        //TODO QUESTION: are native transfers not allowed for starlink only? 
        //! check approval, if insufficient then max approve 
        //TODO Why are we working with max approvals here? to save gas? Cause I thought its recommended to not use them anymore
        LibAsset.maxApproveERC20(IERC20(_bridgeData.sendingAssetId), address(router), _bridgeData.minAmount);

        //! initiate bridging with stargate router
        //! attach bridging fee in native tokens  
        router.swap{ value: _stargateData.lzFee }(
            getLayerZeroChainId(_bridgeData.destinationChainId),    //! layerZero chainId
            getStargatePoolId(_bridgeData.sendingAssetId),          //! source pool ID (=token address but for starlink)
            _stargateData.dstPoolId,                                //! dest pool ID (=token address but for starlink)
            _stargateData.refundAddress,                            //! refund address for extra gas
            _bridgeData.minAmount,                                  //! bridge amount
            _stargateData.minAmountLD,                              //! minAmountOut at destination
            //TODO for starlink this variable seems useless as bridgings are 1:1
            //TODO in test cases this variable is not set so I guess it's at 0, therefore "any amount"?
            IStargateRouter.lzTxObj(_stargateData.dstGasForCall, 0, toBytes(_bridgeData.receiver)),
            _stargateData.callTo,                                   //! receiver addr on dest chain
            _stargateData.callData                                  //! call on dest chain
        );

        emit LiFiTransferStarted(_bridgeData);
        //TODO What happens after this? How does the release work?
    }

    function validateDestinationCallFlag(ILiFi.BridgeData memory _bridgeData, StargateData calldata _stargateData)
        private
        pure
    {
        if ((_stargateData.callData.length > 0) != _bridgeData.hasDestinationCall) {
            revert InformationMismatch();
        }
    }

    /// Mappings management ///

    /// @notice Sets the Stargate pool ID for a given token
    /// @param _token address of the token
    /// @param _poolId uint16 of the Stargate pool ID
    function setStargatePoolId(address _token, uint16 _poolId) external {
        LibDiamond.enforceIsContractOwner();
        LibMappings.StargateMappings storage sm = LibMappings.getStargateMappings();

        if (!sm.initialized) {
            revert NotInitialized();
        }

        sm.stargatePoolId[_token] = _poolId;
        emit StargatePoolIdSet(_token, _poolId);
    }

    /// @notice Sets the Layer 0 chain ID for a given chain ID
    /// @param _chainId uint16 of the chain ID
    /// @param _layerZeroChainId uint16 of the Layer 0 chain ID
    /// @dev This is used to map a chain ID to its Layer 0 chain ID
    function setLayerZeroChainId(uint256 _chainId, uint16 _layerZeroChainId) external {
        LibDiamond.enforceIsContractOwner();
        LibMappings.StargateMappings storage sm = LibMappings.getStargateMappings();

        if (!sm.initialized) {
            revert NotInitialized();
        }

        sm.layerZeroChainId[_chainId] = _layerZeroChainId;
        emit LayerZeroChainIdSet(_chainId, _layerZeroChainId);
    }

    /// @notice Gets the Stargate pool ID for a given token
    /// @param _token address of the token
    /// @return uint256 of the Stargate pool ID
    function getStargatePoolId(address _token) private view returns (uint16) {
        LibMappings.StargateMappings storage sm = LibMappings.getStargateMappings();
        uint16 poolId = sm.stargatePoolId[_token];
        if (poolId == 0) revert UnknownStargatePool();
        return poolId;
    }

    /// @notice Gets the Layer 0 chain ID for a given chain ID
    /// @param _chainId uint256 of the chain ID
    /// @return uint16 of the Layer 0 chain ID
    function getLayerZeroChainId(uint256 _chainId) private view returns (uint16) {
        LibMappings.StargateMappings storage sm = LibMappings.getStargateMappings();
        uint16 chainId = sm.layerZeroChainId[_chainId];
        if (chainId == 0) revert UnknownLayerZeroChain();
        return chainId;
    }

    function toBytes(address _address) private pure returns (bytes memory) {
        bytes memory tempBytes;

        assembly {
            let m := mload(0x40)
            _address := and(_address, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, _address))
            mstore(0x40, add(m, 52))
            tempBytes := m
        }

        return tempBytes;
    }
}
