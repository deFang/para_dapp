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
import {ILpToken} from "../interface/ILpToken.sol";
import {Admin} from "../admin/Admin.sol";
import {LpToken} from "../perpetual/LpToken.sol";


/**
 * @title LiquidityProvider
 * @author Parapara
 *
 * @notice Functions for liquidity provider operations
 */
contract LiquidityProvider is Margin {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    bool private _INITIALIZED_;
    Admin public ADMIN;
    address public _COLLATERAL_POOL_TOKEN_;



    // ============ Events ============
    event LpDeposit(
        address indexed payer,
        address indexed receiver,
        uint256 amount,
        uint256 lpTokenAmount
    );

    event LpWithdraw(
        address indexed payer,
        address indexed receiver,
        uint256 amount,
        uint256 lpTokenAmount
    );


    // ============ Routine Functions ============

    function init(
        address adminAddress,
        address traderAddress,
        string memory tokenName
    ) external {
        require(!_INITIALIZED_, "LIQUIDITY_INITIALIZED");
        _INITIALIZED_ = true;
        ADMIN = Admin(adminAddress);
        _COLLATERAL_POOL_TOKEN_ = address(new LpToken(tokenName));
    }

    /*
     * @dev deposit to LP
     * @param amount amount of collateral token
     */
    function depositCollateral(uint256 amount) external {
        _depositCollateralTo(msg.sender, amount);
    }

    /*
     * @dev withdraw msg.sender's share to account balance given amount of LP token
     * @param amount amount of LP token.
     */
    function withdrawCollateral(uint256 amount) external {
        _withdrawCollateralTo(msg.sender, amount);
    }

    /*
     * @dev withdraw msg.sender's all share to account balance
     * @param amount amount of LP token.
     */
    function withdrawAllCollateral() external {
        _withdrawAllCollateralTo(msg.sender);
    }


    // ============ Deposit Functions ============
    /*
     * @dev Calculate LP share given Collateral amount
     * @param to LP address.
     * @param amount amount of collateral token.
     */
    function _depositCollateralTo(address to, uint256 amount)
        internal
        preventReentrant
    {
        ADMIN.checkNotClosed();
        ADMIN.checkNotPaused();
        ADMIN.depositAllowed();
        Types.MarginAccount memory poolAccount = TRADER._POOL_MARGIN_ACCOUNT_();
        uint256 totalCapital = getTotalCollateralPoolToken();
        uint256 capital;
        if (totalCapital == 0) {
            // give remaining quote token to lp as a gift
            capital = amount;
        }
        else {
            int256 collateralBalance;
            if (poolAccount.SIDE == Types.Side.FLAT) {
                collateralBalance = poolAccount.CASH_BALANCE;
            }
            else {
                collateralBalance = poolAccount.CASH_BALANCE.add(
                    TRADER.queryPNL(
                        Types.oppositeSide(poolAccount.SIDE),
                        poolAccount.SIZE,
                        poolAccount.ENTRY_VALUE,
                        poolAccount.SIZE
                    )
                );
            }
            capital = DecimalMath.mul(DecimalMath.divCeil(amount, collateralBalance.touint256()), totalCapital);
        }

        // settlement
        Types.VirtualBalance memory updateBalance;
        if (poolAccount.SIDE ==  Types.Side.FLAT) {
            updateBalance = TRADER._expectedTargetHelperWhenBalanced(TRADER._QUOTE_BALANCE_().add(amount), ADMIN.getOraclePrice());
        }
        else {
            updateBalance = TRADER._expectedTargetHelperWhenBiased(
                poolAccount.SIDE,
                TRADER._QUOTE_BALANCE_().add(amount),
                ADMIN.getOraclePrice(),
                poolAccount.SIZE,
                ADMIN._K_());
        }
        if (_TARGET_QUOTE_TOKEN_AMOUNT_ != updateBalance.quoteTarget) {
            _TARGET_QUOTE_TOKEN_AMOUNT_ = updateBalance.quoteTarget;
        }
        if (_TARGET_BASE_TOKEN_AMOUNT_ != updateBalance.baseTarget) {
            _TARGET_BASE_TOKEN_AMOUNT_ = updateBalance.baseTarget;
        }
        if (_BASE_BALANCE_ != updateBalance.baseBalance) {
            _BASE_BALANCE_ = updateBalance.baseBalance;
        }
        if (_QUOTE_BALANCE_ != updateBalance.quoteBalance) {
            _QUOTE_BALANCE_ = updateBalance.quoteBalance;
        }

        _marginTransferToPool(to, amount);
        _mintCollateralPoolToken(to, capital);

        emit LpDeposit(msg.sender, to, amount, capital);
    }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      
    // ============ Withdraw Functions ============
    /*
     * @dev Calculate LP share given LP token amount
     * @param to LP address.
     * @param amount amount of LP token.
     */
    function _withdrawCollateralTo(address to, uint256 lpAmount)
        internal
        preventReentrant
    {
        ADMIN.checkNotClosed();
        ADMIN.checkNotPaused();
        // calculate capital
        uint256 totalCapital = getTotalCollateralPoolToken();
        require(totalCapital > 0, "withdrawCollateralTo: NO_LP");
        uint256 cashAmount = DecimalMath.mul(DecimalMath.divCeil(lpAmount, totalCapital), _POOL_MARGIN_ACCOUNT_.CASH_BALANCE.touint256());
        _marginTransferFromPool(to, cashAmount);
        uint256 sizeAmount;
        uint256 valueAmount;
        uint256 r = DecimalMath.divCeil(lpAmount, totalCapital);
        if (_POOL_MARGIN_ACCOUNT_.SIDE != Types.Side.FLAT) {
            sizeAmount = DecimalMath.mul(r, _POOL_MARGIN_ACCOUNT_.SIZE);
            valueAmount = DecimalMath.mul(r, _POOL_MARGIN_ACCOUNT_.ENTRY_VALUE);

            Types.MarginAccount memory traderAccount = _MARGIN_ACCOUNT_[msg.sender];
            Types.MarginAccount memory poolAccount = _POOL_MARGIN_ACCOUNT_;
            traderAccount = trade(traderAccount, _POOL_MARGIN_ACCOUNT_.SIDE, valueAmount, sizeAmount);
            poolAccount = trade(poolAccount, Types.oppositeSide(_POOL_MARGIN_ACCOUNT_.SIDE), valueAmount, sizeAmount);
            _MARGIN_ACCOUNT_[msg.sender] = traderAccount;
            _POOL_MARGIN_ACCOUNT_ = poolAccount;

        }

        Types.VirtualBalance memory updateBalance = getExpectedTarget();
        updateBalance.baseBalance = DecimalMath.mul(updateBalance.baseBalance,DecimalMath.ONE.sub(r));
        updateBalance.baseTarget = DecimalMath.mul(updateBalance.baseTarget,DecimalMath.ONE.sub(r));
        updateBalance.quoteBalance = DecimalMath.mul(updateBalance.quoteBalance,DecimalMath.ONE.sub(r));
        updateBalance.quoteTarget = DecimalMath.mul(updateBalance.quoteTarget,DecimalMath.ONE.sub(r));
        if (_TARGET_QUOTE_TOKEN_AMOUNT_ != updateBalance.quoteTarget) {
            _TARGET_QUOTE_TOKEN_AMOUNT_ = updateBalance.quoteTarget;
        }
        if (_TARGET_BASE_TOKEN_AMOUNT_ != updateBalance.baseTarget) {
            _TARGET_BASE_TOKEN_AMOUNT_ = updateBalance.baseTarget;
        }
        if (_BASE_BALANCE_ != updateBalance.baseBalance) {
            _BASE_BALANCE_ = updateBalance.baseBalance;
        }
        if (_QUOTE_BALANCE_ != updateBalance.quoteBalance) {
            _QUOTE_BALANCE_ = updateBalance.quoteBalance;
        }
        // settlement
        _burnCollateralPoolToken(to, lpAmount);
        emit LpWithdraw(msg.sender, to, cashAmount, lpAmount);
    }

    // ============ Withdraw all Functions ============

    function _withdrawAllCollateralTo(address to)
        internal
    {
        uint256 totalCapital = getTotalCollateralPoolToken();
        require(totalCapital > 0, "withdrawCollateralTo: NO_LP");
        uint256 lpAmount = getCollateralPoolTokenBalanceOf(to);
        _withdrawCollateralTo(to, lpAmount);
    }



    // ============ Helper Functions ============
//    function _calculatePoolEquity() internal view returns (int256 equityBalance) {
//        if (_POOL_MARGIN_ACCOUNT_.SIDE == Types.Side.FLAT) {
//            equityBalance = _POOL_MARGIN_ACCOUNT_.CASH_BALANCE;
//        }
//        else {
//            equityBalance = _POOL_MARGIN_ACCOUNT_.CASH_BALANCE.add(
//                queryPNL(
//                    Types.oppositeSide(_POOL_MARGIN_ACCOUNT_.SIDE),
//                    _POOL_MARGIN_ACCOUNT_.SIZE,
//                    _POOL_MARGIN_ACCOUNT_.ENTRY_VALUE,
//                    _POOL_MARGIN_ACCOUNT_.SIZE
//                )
//            );
//        }
//    }
    // calculate ENP
//    function _poolNetPositionRatio() internal view returns (uint256 ENP) {
//        uint256 poolEquity = _calculatePoolEquity().max(0).touint256();
//        uint256 currentValue = DecimalMath.mul(_POOL_MARGIN_ACCOUNT_.SIZE, ADMIN.getOraclePrice());
//        ENP = DecimalMath.divCeil(poolEquity, currentValue);
//    }
//
//    // POOL 资金仍超过新开仓最低线，可以开新仓
//    function _canPoolOpen() internal view returns (bool) {
//        return _poolNetPositionRatio()>ADMIN._POOL_OPEN_TH_();
//    }
//
//    //  POOL 资金量仍然超过强平线，可以keep
//    function _canPoolKeep() internal view returns (bool) {
//        return _poolNetPositionRatio()>ADMIN._POOL_LIQUIDATE_TH_();
//    }

    function getCollateralPoolTokenBalanceOf(address lp)
        public
        view
        returns (uint256)
    {
        return ILpToken(_COLLATERAL_POOL_TOKEN_).balanceOf(lp);
    }

    function getTotalCollateralPoolToken() public view returns (uint256) {
        return ILpToken(_COLLATERAL_POOL_TOKEN_).totalSupply();
    }

    function _mintCollateralPoolToken(address user, uint256 amount) internal {
        ILpToken(_COLLATERAL_POOL_TOKEN_).mint(user, amount);
    }

    function _burnCollateralPoolToken(address user, uint256 amount) internal {
        ILpToken(_COLLATERAL_POOL_TOKEN_).burn(user, amount);
    }
}
