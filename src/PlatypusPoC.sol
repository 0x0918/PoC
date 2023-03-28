// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "forge-std/Test.sol";
import "forge-std/interfaces/IERC20.sol";

// @Tx(One of the attack transactions)
// https://etherscan.io/tx/

/* ========== Basic Information ========== */
abstract contract Base {
    IERC20 internal constant  ERC20 = IERC20();   
}


/* ========== Attack Test ========== */
contract ContractTest is Test, Base {
    
    function setUp() public {
        vm.createSelectFork("mainnet", );
        vm.label(address(), "");
    }

    function testStart() public {
    }

    function executeOperation(
        address[] memory assets, 
        uint256[] memory amounts, 
        uint256[] memory premiums, 
        address initiator, 
        bytes memory params
        )external returns (bool) {
            return true;
        } 
}
