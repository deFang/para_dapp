/*

    Copyright 2021 ParaPara
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

interface IOracle {
    function getPrice() external view returns (uint256);
}
