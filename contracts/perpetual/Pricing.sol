/*

    Copyright 2021 ParaPara
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../lib/SafeMath.sol";
import {SignedSafeMath} from "../lib/SignedSafeMath.sol";
import {DecimalMath} from "../lib/DecimalMath.sol";
import {PMMCurve} from "../lib/PMMCurve.sol";
import {Types} from "../lib/Types.sol";
import {Account} from "./Account.sol";
import {Admin} from "../admin/Admin.sol";


/**
 * @title Pricing
 * @author Parapara
 *
 * @notice Parapara Pricing model
 */
contract Pricing {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    bool internal _INITIALIZED_;
    Account internal ACCOUNT;
    Admin internal ADMIN;

    function init(
        address accountAddress,
        address adminAddress
    ) external {
        require(!_INITIALIZED_, "PRICE_INITIALIZED");
        _INITIALIZED_ = true;
        ACCOUNT = Account(accountAddress);
        ADMIN = Admin(adminAddress);
    }

    // ============ Helper functions ============
    function _expectedTargetHelperWhenBiased(
        Types.Side side,
        uint256 quoteBalance,
        uint256 price,
        uint256 deltaB,
        uint256 _K_
    ) internal pure returns (
        uint256, uint256, uint256, uint256, Types.Side
    ) {
        uint256 baseTarget;
        uint256 quoteTarget;
        if (side == Types.Side.SHORT) {
            (baseTarget, quoteTarget) = PMMCurve._RegressionTargetWhenShort(quoteBalance, price, deltaB, _K_);
            return (baseTarget, baseTarget.sub(deltaB), quoteTarget, quoteBalance, Types.Side.SHORT);
        }
        else if (side == Types.Side.LONG) {
            (baseTarget, quoteTarget) = PMMCurve._RegressionTargetWhenLong(quoteBalance, price, deltaB, _K_);
            return (baseTarget, baseTarget.add(deltaB), quoteTarget, quoteBalance, Types.Side.LONG);
        }
    }

    function _expectedTargetHelperWhenBalanced(uint256 quoteBalance, uint256 price) internal pure returns (
        uint256, uint256, uint256, uint256, Types.Side
    ) {
        uint256 baseTarget = DecimalMath.divFloor(quoteBalance, price);
        return (baseTarget, baseTarget, quoteBalance, quoteBalance, Types.Side.FLAT);
    }


    function getExpectedTarget()
        public
        view
        returns (uint256, uint256, uint256, uint256, Types.Side)
    {
        if (ACCOUNT.getPoolMarginSide() ==  Types.Side.FLAT) {
            return _expectedTargetHelperWhenBalanced(ACCOUNT._QUOTE_BALANCE_(), ADMIN.getOraclePrice());
        }
        else {
            return _expectedTargetHelperWhenBiased(ACCOUNT.getPoolMarginSide(), ACCOUNT._QUOTE_BALANCE_(), ADMIN.getOraclePrice(), ACCOUNT.getPoolMarginSize(), ADMIN._K_());
        }
    }

    function getExpectedTargetExt(
        Types.Side side,
        uint256 quoteBalance,
        uint256 price,
        uint256 deltaB,
        uint256 _K_
    )
        public
        pure
        returns (uint256, uint256, uint256, uint256, Types.Side) {
        if (side ==  Types.Side.FLAT) {
            return _expectedTargetHelperWhenBalanced(quoteBalance, price);
        }
        else {
            return _expectedTargetHelperWhenBiased(
                side,
                quoteBalance,
                price,
                deltaB,
                _K_);
        }
    }



    function getMidPrice() public view returns (uint256 midPrice) {
        (uint256 baseTarget, uint256 baseBalance, uint256 quoteTarget, uint256 quoteBalance, ) = getExpectedTarget();
        uint256 K = ADMIN._K_();
        if (ACCOUNT._R_STATUS_() == Types.Side.LONG) {
            uint256 R =
                DecimalMath.divFloor(
                    quoteTarget.mul(quoteTarget).div(quoteBalance),
                    quoteBalance
                );
            R = DecimalMath.ONE.sub(K).add(DecimalMath.mul(K, R));
            return DecimalMath.divFloor(ADMIN.getOraclePrice(), R);
        } else {
            uint256 R =
                DecimalMath.divFloor(
                    baseTarget.mul(baseTarget).div(baseBalance),
                    baseBalance
                );
            R = DecimalMath.ONE.sub(K).add(DecimalMath.mul(K, R));
            return DecimalMath.mul(ADMIN.getOraclePrice(), R);
        }
    }

    // ============ Query Functions ============
    function queryPNLwiValue(
        Types.Side accountSide,
        uint256 entryValue,
        uint256 closeValue,
        uint256 entrySloss,
        uint256 clossSloss
    ) public pure returns (int256) {
        int256 sloss = clossSloss.toint256().sub(entrySloss.toint256());
        int256 PNL =
            accountSide == Types.Side.LONG
                ? closeValue.toint256().sub(entryValue.toint256())
                : entryValue.toint256().sub(closeValue.toint256());
        return PNL.sub(sloss);
    }

    // calculate pnl given the amount of position to be closed
    // equates to Unrealized PNL when amount == accountSize
    function queryPNL(
        Types.Side accountSide,
        uint256 accountSize,
        uint256 accountEntryValue,
        uint256 amount,
        uint256 accountEntrySloss
    ) public view returns (int256) {
        if (accountSize == 0) {
            return 0;
        }
        uint256 entryValue;
        uint256 entrySloss;
        if (amount == accountSize) {
            entryValue = accountEntryValue;
            entrySloss = accountEntrySloss;
        } else {
            entryValue =
                DecimalMath.mul(accountEntryValue, DecimalMath.divFloor(amount, accountSize));
            entrySloss =
                DecimalMath.mul(accountEntrySloss, DecimalMath.divFloor(amount, accountSize));
        }
        uint256 closeSloss = DecimalMath.mul(ACCOUNT.getSloss()[uint256(accountSide)], amount);
        uint256 closeValue = closePositionValue(accountSide, amount);
        return queryPNLwiValue(accountSide, entryValue, closeValue, entrySloss, closeSloss);
    }



    //
    function closePositionValue(
        Types.Side side,
        uint256 amount
    ) public view returns (uint256 closeValue) {
        if (side == Types.Side.LONG) {
            closeValue = querySellBaseToken(amount);
        }
        else if (side == Types.Side.SHORT) {
            closeValue = queryBuyBaseToken(amount);
        }
        else {
            closeValue = 0;
        }
    }


    function queryPNLMarkPrice(
        Types.Side accountSide,
        uint256 accountSize,
        uint256 accountEntryValue,
        uint256 amount,
        uint256 accountEntrySloss
    ) public view returns (int256) {
        if (accountSize == 0) {
            return 0;
        }
        uint256 entryValue;
        uint256 entrySloss;
        if (amount == accountSize) {
            entryValue = accountEntryValue;
            entrySloss = accountEntrySloss;
        } else {
            entryValue =
                DecimalMath.mul(accountEntryValue, DecimalMath.divFloor(amount, accountSize));
            entrySloss =
                DecimalMath.mul(accountEntrySloss, DecimalMath.divFloor(amount, accountSize));
        }
        uint256 closeSloss = DecimalMath.mul(ACCOUNT.getSloss()[uint256(accountSide)], amount);
        uint256 closeValue = DecimalMath.mul(amount, ADMIN.getOraclePrice());
        return queryPNLwiValue(accountSide, entryValue, closeValue, entrySloss, closeSloss);
    }

    function querySellBaseToken(uint256 amount)
        public
        view
        returns (uint256 receiveQuote)
    {
        (receiveQuote, , , , , , ,) = _querySellBaseToken(amount);
        return receiveQuote;
    }

    function queryBuyBaseToken(uint256 amount)
        public
        view
        returns (uint256 payQuote)
    {
        (payQuote, , , , , , , ) = _queryBuyBaseToken(amount);
        return payQuote;
    }


    function _sellHelperRAboveOne(
        uint256 sellBaseAmount,
        uint256 K,
        uint256 price,
        uint256 baseTarget,
        uint256 baseBalance,
        uint256 quoteTarget
    ) internal view returns (
        uint256 receiveQuote,
        Types.Side newSide,
        uint256 newDeltaB)
    {
        uint256 backToOnePayBase = baseTarget.sub(baseBalance);

        // case 2: R>1
        // complex case, R status depends on trading amount
        if (sellBaseAmount < backToOnePayBase) {
            // case 2.1: R status do not change
            receiveQuote = PMMCurve._RAboveSellBaseToken(
                price,
                K,
                sellBaseAmount,
                baseBalance,
                baseTarget
            );
            newSide = Types.Side.SHORT;
            newDeltaB = ACCOUNT.getPoolMarginSize().sub(sellBaseAmount);
            uint256 backToOneReceiveQuote = PMMCurve._RAboveSellBaseToken(price, K, backToOnePayBase, baseBalance, baseTarget);
            if (receiveQuote > backToOneReceiveQuote) {
                // [Important corner case!] may enter this branch when some precision problem happens. And consequently contribute to negative spare quote amount
                // to make sure spare quote>=0, mannually set receiveQuote=backToOneReceiveQuote
                receiveQuote = backToOneReceiveQuote;
            }
        }
        else if (sellBaseAmount == backToOnePayBase) {
            // case 2.2: R status changes to ONE
            receiveQuote = PMMCurve._RAboveSellBaseToken(price, K, backToOnePayBase, baseBalance, baseTarget);
            newSide = Types.Side.FLAT;
            newDeltaB = 0;
        }
        else {
            // case 2.3: R status changes to BELOW_ONE
            {
                receiveQuote = PMMCurve._RAboveSellBaseToken(price, K, backToOnePayBase, baseBalance, baseTarget).add(
                    PMMCurve._ROneSellBaseToken(
                        price,
                        K,
                        sellBaseAmount.sub(backToOnePayBase),
                        quoteTarget
                    )
                );
            }
            newSide = Types.Side.LONG;
            newDeltaB = sellBaseAmount.sub(backToOnePayBase); // newDeltaB = sellBaseAmount.sub(_POOL_MARGIN_ACCOUNT.SIZE)?
        }
    }

    function _querySellBaseToken(uint256 sellBaseAmount)
        public
        view
        returns (
            uint256 receiveQuote,
            uint256 lpFeeQuote,
            uint256 mtFeeQuote,
            uint256 baseTarget,
            uint256 baseBalance,
            uint256 quoteTarget,
            uint256 quoteBalance,
            Types.Side newSide
        )
    {
        (baseTarget, baseBalance, quoteTarget, quoteBalance,) = getExpectedTarget();
        uint256 price = ADMIN.getOraclePrice();
        uint256 K = ADMIN._K_();
        uint256 newDeltaB;

        if (ACCOUNT._R_STATUS_() == Types.Side.FLAT) {
            // case 1: R=1
            // R falls below one
            receiveQuote = PMMCurve._ROneSellBaseToken(price, K, sellBaseAmount, quoteTarget);
            newSide = Types.Side.LONG;
            newDeltaB = sellBaseAmount;
        }
        else if (ACCOUNT._R_STATUS_() == Types.Side.SHORT) {
            (receiveQuote, newSide, newDeltaB) = _sellHelperRAboveOne(sellBaseAmount, K, price, baseTarget, baseBalance, quoteTarget);
        } else {
            // ACCOUNT._R_STATUS_() == Types.Side.LONG
            // case 3: R<1
            receiveQuote = PMMCurve._RBelowSellBaseToken(
                price,
                K,
                sellBaseAmount,
                quoteBalance,
                quoteTarget
            );
            newSide = Types.Side.LONG;
            newDeltaB = ACCOUNT.getPoolMarginSize().add(sellBaseAmount);
        }

        // count fees
        lpFeeQuote = DecimalMath.mul(receiveQuote, ADMIN._LP_FEE_RATE_());
        mtFeeQuote = DecimalMath.mul(receiveQuote, ADMIN._MT_FEE_RATE_());

        if (newSide == Types.Side.FLAT) {
            (baseTarget, baseBalance, quoteTarget, quoteBalance,) = _expectedTargetHelperWhenBalanced(ACCOUNT._QUOTE_BALANCE_().sub(receiveQuote).add(lpFeeQuote), price);
        } else {
            (baseTarget, baseBalance, quoteTarget, quoteBalance,) = _expectedTargetHelperWhenBiased(newSide, ACCOUNT._QUOTE_BALANCE_().sub(receiveQuote).add(lpFeeQuote), price, newDeltaB, K);
        }

        return (
            receiveQuote,
            lpFeeQuote,
            mtFeeQuote,
            baseTarget,
            baseBalance,
            quoteTarget,
            quoteBalance,
            newSide
        );
    }

    // to avoid stack too deep
    function _buyHelperRBelowOne(
        uint256 buyBaseAmount,
        uint256 K,
        uint256 price,
        uint256 backToOneReceiveBase,
        uint256 baseTarget,
        uint256 quoteTarget,
        uint256 quoteBalance
    ) internal view returns (
        uint256 payQuote,
        Types.Side newSide,
        uint256 newDeltaB
    ) {
        // case 3: R<1
        // complex case, R status may change
        if (buyBaseAmount < backToOneReceiveBase) {
            // case 3.1: R status do not change
            // no need to check payQuote because spare base token must be greater than zero
            payQuote = PMMCurve._RBelowBuyBaseToken(
                price,
                K,
                buyBaseAmount,
                quoteBalance,
                quoteTarget
            );

            newSide = Types.Side.LONG;
            newDeltaB = ACCOUNT.getPoolMarginSize().sub(buyBaseAmount);

        } else if (buyBaseAmount == backToOneReceiveBase) {
            // case 3.2: R status changes to ONE
            payQuote = PMMCurve._RBelowBuyBaseToken(price, K, backToOneReceiveBase, quoteBalance, quoteTarget);
            newSide = Types.Side.FLAT;
            newDeltaB = 0;
        } else {
            // case 3.3: R status changes to ABOVE_ONE
            uint256 addQuote = PMMCurve._ROneBuyBaseToken(
                price,
                K,
                buyBaseAmount.sub(backToOneReceiveBase),
                baseTarget);
            payQuote = PMMCurve._RBelowBuyBaseToken(price, K, backToOneReceiveBase, quoteBalance, quoteTarget).add(addQuote);
            newSide = Types.Side.SHORT;
            newDeltaB = buyBaseAmount.sub(backToOneReceiveBase);
        }
    }


    function _queryBuyBaseToken(uint256 buyBaseAmount)
        public
        view
        returns (
            uint256 payQuote,
            uint256 lpFeeQuote,
            uint256 mtFeeQuote,
            uint256 baseTarget,
            uint256 baseBalance,
            uint256 quoteTarget,
            uint256 quoteBalance,
            Types.Side newSide
        )
    {
        (baseTarget, baseBalance, quoteTarget, quoteBalance,) = getExpectedTarget();
        uint256 price = ADMIN.getOraclePrice();
        uint256 K = ADMIN._K_();
        uint256 newDeltaB;
        {
            if (ACCOUNT._R_STATUS_() == Types.Side.FLAT) {
                // case 1: R=1
                payQuote = PMMCurve._ROneBuyBaseToken(price, K, buyBaseAmount, baseTarget);
                newSide = Types.Side.SHORT;
                newDeltaB = buyBaseAmount;
            } else if (ACCOUNT._R_STATUS_() == Types.Side.SHORT) {
                // case 2: R>1
                payQuote = PMMCurve._RAboveBuyBaseToken(
                    price,
                    K,
                    buyBaseAmount,
                    baseBalance,
                    baseTarget
                );
                newSide = Types.Side.SHORT;
                newDeltaB = ACCOUNT.getPoolMarginSize().add(buyBaseAmount);
            } else if (ACCOUNT._R_STATUS_() == Types.Side.LONG) {
                (payQuote, newSide, newDeltaB) = _buyHelperRBelowOne(buyBaseAmount, K, price, baseBalance.sub(baseTarget), baseTarget, quoteTarget, quoteBalance);
            }
        }

        lpFeeQuote = DecimalMath.mul(payQuote, ADMIN._LP_FEE_RATE_());
        mtFeeQuote = DecimalMath.mul(payQuote, ADMIN._MT_FEE_RATE_());

        if (newSide == Types.Side.FLAT) {
            (baseTarget, baseBalance, quoteTarget, quoteBalance,) = _expectedTargetHelperWhenBalanced(ACCOUNT._QUOTE_BALANCE_().add(payQuote).add(lpFeeQuote), price);
        } else {
            (baseTarget, baseBalance, quoteTarget, quoteBalance,) = _expectedTargetHelperWhenBiased(newSide, ACCOUNT._QUOTE_BALANCE_().add(payQuote).add(lpFeeQuote), price, newDeltaB, K);
        }

        return (
            payQuote,
            lpFeeQuote,
            mtFeeQuote,
            baseTarget,
            baseBalance,
            quoteTarget,
            quoteBalance,
            newSide
        );
    }

}
