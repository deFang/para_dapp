/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../lib/SafeMath.sol";
import {SignedSafeMath} from "../lib/SignedSafeMath.sol";
import {DecimalMath} from "../lib/DecimalMath.sol";
import {Types} from "../lib/Types.sol";
import {Settlement} from "./Settlement.sol";
import {IAdmin} from "../interface/IAdmin.sol";


/**
 * @title Pricing
 * @author Parapara
 *
 * @notice Parapara's margin account model
 */
contract Margin is Settlement {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    // ============ Events ============

    event Deposit(address indexed trader, uint256 amount, int256 balance);

    event Withdraw(address indexed trader, uint256 amount, int256 balance);
    
    event Liquidate(address indexed trader, address indexed liquidator, Types.Side liquidationSide, uint256 liquidationValue, uint256 liquidationAmount);

    event InternalUpdateBalance(
        address indexed trader,
        int256 amount,
        int256 balanceAfter
    );

    // ============ Query Functions ============
    // 初始保证金
    function initialMargin(
        uint256 amount,
        uint256 markPrice
    ) public view returns (uint256) {
        return DecimalMath.mul(DecimalMath.mul(markPrice, amount), ADMIN._INITIAL_MARGIN_RATE_());
    }
    // 维持保证金
    function maintenanceMargin(
        uint256 amount,
        uint256 markPrice
    ) public view returns (uint256) {
        return DecimalMath.mul(DecimalMath.mul(markPrice, amount), ADMIN._MAINTENANCE_MARGIN_RATE_());
    }


    // PNL
    // 保证金余额
    // CASH_BALANCE + UNREALIZED_PNL
    function balanceMargin(Types.MarginAccount memory account)
        public view returns (int256) {
        return account.CASH_BALANCE.add(PRICING.queryPNL(account.SIDE, account.SIZE, account.ENTRY_VALUE, account.SIZE));
    }

    // 可用保证金
    function availableMargin(
        Types.MarginAccount memory account,
        uint256 markPrice
    ) public view returns (int256) {
        return balanceMargin(account).sub(initialMargin(account.SIZE, markPrice).toint256());
    }

    // 当前保证金余额是否大于维持保证金，若小于则被强平
    function isSafeMaintain(
        address trader
    ) public view returns (bool) {
        Types.MarginAccount memory account = _MARGIN_ACCOUNT_[trader];
        return balanceMargin(account) > maintenanceMargin(account.SIZE, PRICING.getMidPrice()).toint256(); // 此处应该用mark price
    }


    // 当前可用保证金>新开仓初始保证金
    function isSafeOpen(
        Types.MarginAccount memory account,
        uint256 openValue
    ) public view returns (bool) {
        return availableMargin(account, PRICING.getMidPrice()) > DecimalMath.mul(openValue, ADMIN._INITIAL_MARGIN_RATE_()).toint256();
    }

    // ============ Margin Account Ops ============
    function _open(
        Types.MarginAccount memory account,
        Types.Side side,
        uint256 amount,
        uint256 entryValue
    ) internal returns (Types.MarginAccount memory) {
        require(amount > 0, "open: invalid amount");
//        require(checkTradeEligibility(account, entryValue), "open: INSUFFICIENT FUNDS");
        if (account.SIZE == 0) {
            account.SIDE = side;
        }
        account.SIZE = account.SIZE.add(amount);
        account.ENTRY_VALUE = account.ENTRY_VALUE.add(entryValue);

        return account;
    }


    function _close(
        Types.MarginAccount memory account,
        uint256 amount,
        uint256 closeValue
    ) internal returns (Types.MarginAccount memory) {
        require(amount > 0, "close: invalid amount");

        uint256 entryValue;
        if (amount == account.SIZE) {
            entryValue = account.ENTRY_VALUE;
        } else {
            entryValue =
                DecimalMath.mul(account.ENTRY_VALUE, DecimalMath.divFloor(amount, account.SIZE));
        }
        int256 realizedPNL = PRICING.queryPNLwiValue(account.SIDE, entryValue, closeValue);
        account.CASH_BALANCE = account.CASH_BALANCE.add(realizedPNL);
        account.ENTRY_VALUE = DecimalMath.mul(account.ENTRY_VALUE, DecimalMath.divFloor(account.SIZE.sub(amount), account.SIZE));
        account.SIZE = account.SIZE.sub(amount);
        if (account.SIZE == 0) {
            account.SIDE = Types.Side.FLAT;
        }
        return account;
    }

     /**
     * @dev open long/short position for a trader
     * @param account trader account
     * @param side Long/Short
     * @param amount the amount of position
     */
    function trade(
        Types.MarginAccount memory account,
        Types.Side side,
        uint256 value,
        uint256 amount
    ) internal returns (Types.MarginAccount memory) {
        uint256 closeValue;
        uint256 openAmount = amount;
        if (account.SIZE > 0 && account.SIDE != side) {
            if (amount <= account.SIZE) {
                account = _close(account, amount, value);
                openAmount = 0;
            }
            else {
                closeValue = DecimalMath.mul(value, DecimalMath.divCeil(account.SIZE, amount));
                account = _close(account, account.SIZE, closeValue);
                openAmount = amount.sub(account.SIZE);
            }
        }
        if (openAmount > 0) {
           account = _open(account, side, openAmount, value.sub(closeValue));
        }
        return account;
    }

    function tradePool(
        Types.Side side,
        uint256 value,
        uint256 amount
    ) internal returns (uint256) {
        uint256 closeValue;
        uint256 openAmount = amount;
        Types.MarginAccount memory poolAccount = _POOL_MARGIN_ACCOUNT_;
        if (poolAccount.SIZE > 0 && poolAccount.SIDE != side) {
            if (amount <= poolAccount.SIZE) {
                _close(poolAccount, amount, value);
                openAmount = 0;
            }
            else {
                closeValue = DecimalMath.mul(value, DecimalMath.divCeil(poolAccount.SIZE, amount));
                _close(poolAccount, poolAccount.SIZE, closeValue);
                openAmount = amount.sub(poolAccount.SIZE);
            }
        }

        if (openAmount > 0) {
           _open(poolAccount, side, openAmount, value.sub(closeValue));
        }
        _POOL_MARGIN_ACCOUNT_ = poolAccount;
        return openAmount;
    }


    /**
     * @dev liquidate trader's position from a liquidator
     * @param liquidator the liquidator
     * @param trader the trader to be liquidated
    */
    function _liquidate(
        address liquidator,
        address trader,
        uint256 liquidationValue,
        uint256 liquidationAmount
    ) internal {
        // liquidiated trader
        Types.MarginAccount memory liquidatorAccount = _MARGIN_ACCOUNT_[liquidator];
        Types.MarginAccount memory traderAccount = _MARGIN_ACCOUNT_[trader];
        Types.MarginAccount memory poolAccount = _POOL_MARGIN_ACCOUNT_;
        Types.Side liquidationSide = traderAccount.SIDE;
        int256 penaltyToLiquidator = DecimalMath.mul(ADMIN._LIQUIDATION_PENALTY_RATE_(), liquidationValue).toint256();
        int256 penaltyToPool = DecimalMath.mul(ADMIN._LIQUIDATION_PENALTY_POOL_RATE_(), liquidationValue).toint256();

        // position: trader => liquidator
        traderAccount = trade(
            traderAccount,
            Types.oppositeSide(liquidationSide),
            liquidationValue,
            liquidationAmount
        );

        liquidatorAccount = trade(
                liquidatorAccount,
                liquidationSide,
                liquidationValue,
                liquidationAmount
            );

        if (traderAccount.CASH_BALANCE >= penaltyToLiquidator.add(penaltyToPool)) {
            // 1) cash > penaltyToPool + penaltyToLiquidator
            traderAccount.CASH_BALANCE = traderAccount.CASH_BALANCE.sub(penaltyToLiquidator).sub(penaltyToPool);
            liquidatorAccount.CASH_BALANCE = liquidatorAccount.CASH_BALANCE.add(penaltyToLiquidator);
            poolAccount.CASH_BALANCE = poolAccount.CASH_BALANCE.add(penaltyToPool);
        } else if (traderAccount.CASH_BALANCE >= penaltyToLiquidator) {
            // 2) penaltyToPool + penaltyToLiquidator> cash >penaltyToLiquidator
            poolAccount.CASH_BALANCE = poolAccount.CASH_BALANCE.add(traderAccount.CASH_BALANCE.sub(penaltyToLiquidator));
            liquidatorAccount.CASH_BALANCE = liquidatorAccount.CASH_BALANCE.add(penaltyToLiquidator);
            traderAccount.CASH_BALANCE = 0;
        } else if (traderAccount.CASH_BALANCE >= 0) {
            liquidatorAccount.CASH_BALANCE = liquidatorAccount.CASH_BALANCE.add(traderAccount.CASH_BALANCE);
            traderAccount.CASH_BALANCE = 0;
        } else {
            // TODO
        }

        _MARGIN_ACCOUNT_[trader] = traderAccount;
        _MARGIN_ACCOUNT_[liquidator] = liquidatorAccount;
        if (poolAccount.CASH_BALANCE == _POOL_MARGIN_ACCOUNT_.CASH_BALANCE) {
            _POOL_MARGIN_ACCOUNT_ = poolAccount;
        }
        
        emit Liquidate(liquidator, trader, liquidationSide, liquidationValue, liquidationAmount);
    }


    function liquidate(
        address liquidator,
        address trader
    ) external {
        require(!isSafeMaintain(trader), "SAFE_TO_MAINTAIN");
        Types.MarginAccount memory liquidatorAccount = _MARGIN_ACCOUNT_[liquidator];
        Types.MarginAccount memory traderAccount = _MARGIN_ACCOUNT_[trader];
        uint256 liquidationValue = PRICING.closePositionValue(traderAccount.SIDE, traderAccount.SIZE);
        require(isSafeOpen(liquidatorAccount, liquidationValue), "LIQUIDATOR_NOT_ENOUGH_FUND");
        _liquidate(liquidator, trader, liquidationValue, traderAccount.SIZE);
    }


    function _updateCashBalance(
        Types.MarginAccount memory account,
        int256 amount
    ) internal returns (Types.MarginAccount memory) {
        if (amount == 0) {
            return account;
        }
        account.CASH_BALANCE = account.CASH_BALANCE.add(amount);

        return account;
    }


    /*
     * @dev margin transfer to pool
     * @param from trader address
     * @param amount collateral amount
     */
    function _marginTransferToPool(address from, uint256 amount) internal {
        require(amount > 0, "MarginTransferToPool_ILLEGAL_AMOUNT");
        _MARGIN_ACCOUNT_[from].CASH_BALANCE = _MARGIN_ACCOUNT_[from].CASH_BALANCE.sub(amount.toint256()); // may be negative balance
        _POOL_MARGIN_ACCOUNT_.CASH_BALANCE = _POOL_MARGIN_ACCOUNT_.CASH_BALANCE.add(amount.toint256());
    }

    /*
     * @dev margin transfer from pool
     * @param from trader address
     * @param amount collateral amount
     */
    function _marginTransferFromPool(address to, uint256 amount) internal {
        require(amount > 0, "MarginTransferFromPool_ILLEGAL_AMOUNT");
        _POOL_MARGIN_ACCOUNT_.CASH_BALANCE = _POOL_MARGIN_ACCOUNT_.CASH_BALANCE.sub(amount.toint256());
        _MARGIN_ACCOUNT_[to].CASH_BALANCE = _MARGIN_ACCOUNT_[to].CASH_BALANCE.add(amount.toint256()); // may be negative balance
    }

    /*
     * @dev margin transfer from A to B
     * @param from A
     * @param to B
     * @param amount collateral amount
     */
    function _marginTransferTo(address from, address to, uint256 amount) internal {
        require(amount > 0, "MarginTransferToPool_ILLEGAL_AMOUNT");
        _MARGIN_ACCOUNT_[from].CASH_BALANCE = _MARGIN_ACCOUNT_[from].CASH_BALANCE.sub(amount.toint256()); // may be negative balance
        _MARGIN_ACCOUNT_[to].CASH_BALANCE = _MARGIN_ACCOUNT_[to].CASH_BALANCE.add(amount.toint256());
    }

}