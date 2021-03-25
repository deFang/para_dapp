/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;


import {IPara} from "../interface/IPara.sol";


// Oracle only for test
contract Liquidator {

    uint256 public tokenPrice;

    function getPrice() external view returns (uint256) {
        return tokenPrice;
    }
}
