/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {InitializableOwnable} from "../lib/InitializableOwnable.sol";
import {ReentrancyGuard} from "../lib/ReentrancyGuard.sol";
import {Types} from "../lib/Types.sol";
import {Admin} from "../admin/Admin.sol";
import {Pricing} from "./Pricing.sol";

/**
 * @title Storage
 * @author Parapara
 *
 * @notice Local Variables
 */
contract Account is InitializableOwnable, ReentrancyGuard {
    // ============ Variables for Control ============
    bool internal _INITIALIZED_;
    Admin public ADMIN;
    Pricing public PRICING;
    address public _COLLATERAL_POOL_TOKEN_;
    Types.MarginAccount public _POOL_MARGIN_ACCOUNT_;
    mapping(address => Types.MarginAccount) public _MARGIN_ACCOUNT_;
    uint256 public _TARGET_BASE_TOKEN_AMOUNT_;
    uint256 public _TARGET_QUOTE_TOKEN_AMOUNT_;
    uint256 public _BASE_BALANCE_;
    uint256 public _QUOTE_BALANCE_;
    Types.Side public _R_STATUS_ = Types.Side.FLAT;

    uint256 public _POOL_INSURANCE_BALANCE_;

    function getPoolMarginSide() external view returns (Types.Side) {
        return _POOL_MARGIN_ACCOUNT_.SIDE;
    }

    function getPoolMarginCashBalance() external view returns (int256) {
        return _POOL_MARGIN_ACCOUNT_.CASH_BALANCE;
    }

    function getPoolMarginSize() external view returns (uint256) {
        return _POOL_MARGIN_ACCOUNT_.SIZE;
    }

    function getPoolMarginEntryValue() external view returns (uint256) {
        return _POOL_MARGIN_ACCOUNT_.ENTRY_VALUE;
    }

    function updateVirtualBalance (
        uint256 baseTarget,
        uint256 baseBalance,
        uint256 quoteTarget,
        uint256 quoteBalance,
        Types.Side newSide
        ) internal {
        if (_TARGET_QUOTE_TOKEN_AMOUNT_ != quoteTarget) {
            _TARGET_QUOTE_TOKEN_AMOUNT_ = quoteTarget;
        }
        if (_TARGET_BASE_TOKEN_AMOUNT_ != baseTarget) {
            _TARGET_BASE_TOKEN_AMOUNT_ = baseTarget;
        }
        if (_BASE_BALANCE_ != baseBalance) {
            _BASE_BALANCE_ = baseBalance;
        }
        if (_QUOTE_BALANCE_ != quoteBalance) {
            _QUOTE_BALANCE_ = quoteBalance;
        }
        if (_R_STATUS_ != newSide) {
            _R_STATUS_ = newSide;
        }
    }
}
