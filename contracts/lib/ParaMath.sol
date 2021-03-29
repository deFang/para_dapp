/*

    Copyright 2021 ParaPara
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {SafeMath} from "./SafeMath.sol";
import {DecimalMath} from "./DecimalMath.sol";

/**
 * @title ParaMath
 * @author Parapara
 *
 * @notice Functions for complex calculating. Including ONE Integration and TWO Quadratic solutions
 */
library ParaMath {
    using SafeMath for uint256;

    /*
        Integrate dodo curve fron V1 to V2
        require V0>=V1>=V2>0
        res = (1-k)i(V1-V2)+ikV0*V0(1/V2-1/V1)
        let V1-V2=delta
        res = i*delta*(1-k+k(V0^2/V1/V2))
    */
    function _GeneralIntegrate(
        uint256 V0,
        uint256 V1,
        uint256 V2,
        uint256 i,
        uint256 k
    ) internal pure returns (uint256) {
        uint256 fairAmount = DecimalMath.mul(i, V1.sub(V2)); // i*delta
        uint256 V0V0V1V2 = DecimalMath.divCeil(V0.mul(V0).div(V1), V2);
        uint256 penalty = DecimalMath.mul(k, V0V0V1V2); // k(V0^2/V1/V2)
        return DecimalMath.mul(fairAmount, DecimalMath.ONE.sub(k).add(penalty));
    }

    /*
        The same with integration expression above, we have:
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Given Q1 and deltaB, solve Q2
        This is a quadratic function and the standard version is
        aQ2^2 + bQ2 + c = 0, where
        a=1-k
        -b=(1-k)Q1-kQ0^2/Q1+i*deltaB
        c=-kQ0^2
        and Q2=(-b+sqrt(b^2+4(1-k)kQ0^2))/2(1-k)
        note: another root is negative, abondan
        if deltaBSig=true, then Q2>Q1
        if deltaBSig=false, then Q2<Q1
    */
    function _SolveQuadraticFunctionForTrade(
        uint256 Q0,
        uint256 Q1,
        uint256 ideltaB,
        bool deltaBSig,
        uint256 k
    ) internal pure returns (uint256) {
        // calculate -b value and sig
        // -b = (1-k)Q1-kQ0^2/Q1+i*deltaB
        uint256 kQ02Q1 = DecimalMath.mul(k, Q0).mul(Q0).div(Q1); // kQ0^2/Q1
        uint256 b = DecimalMath.mul(DecimalMath.ONE.sub(k), Q1); // (1-k)Q1
        bool minusbSig = true;
        if (deltaBSig) {
            b = b.add(ideltaB); // (1-k)Q1+i*deltaB
        } else {
            kQ02Q1 = kQ02Q1.add(ideltaB); // i*deltaB+kQ0^2/Q1
        }
        if (b >= kQ02Q1) {
            b = b.sub(kQ02Q1);
            minusbSig = true;
        } else {
            b = kQ02Q1.sub(b);
            minusbSig = false;
        }

        // calculate sqrt
        uint256 squareRoot =
            DecimalMath.mul(
                DecimalMath.ONE.sub(k).mul(4),
                DecimalMath.mul(k, Q0).mul(Q0)
            ); // 4(1-k)kQ0^2
        squareRoot = b.mul(b).add(squareRoot).sqrt(); // sqrt(b*b+4(1-k)kQ0*Q0)

        // final res
        uint256 denominator = DecimalMath.ONE.sub(k).mul(2); // 2(1-k)
        uint256 numerator;
        if (minusbSig) {
            numerator = b.add(squareRoot);
        } else {
            numerator = squareRoot.sub(b);
        }

        if (deltaBSig) {
            return DecimalMath.divFloor(numerator, denominator);
        } else {
            return DecimalMath.divCeil(numerator, denominator);
        }
    }

    /*
        Start from the integration function
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Assume Q2=Q0, Given Q1 and deltaB, solve Q0
        let fairAmount = i*deltaB
    */
    function _SolveQuadraticFunctionForTarget(
        uint256 V1,
        uint256 k,
        uint256 fairAmount
    ) internal pure returns (uint256 V0) {
        // V0 = V1+V1*(sqrt-1)/2k
        uint256 sqrt =
            DecimalMath.divCeil(DecimalMath.mul(k, fairAmount).mul(4), V1);
        sqrt = sqrt.add(DecimalMath.ONE).mul(DecimalMath.ONE).sqrt();
        uint256 premium =
            DecimalMath.divCeil(sqrt.sub(DecimalMath.ONE), k.mul(2));
        // V0 is greater than or equal to V1 according to the solution
        return DecimalMath.mul(V1, DecimalMath.ONE.add(premium));
    }

    /*
        Update BaseTarget when AMM holds short position
        given oracle price
        B0 == Q0 / price
    */
    function _RegressionTargetWhenShort(
        uint256 Q1,
        uint256 price,
        uint256 deltaB,
        uint256 k
    )
        internal pure returns (uint256 B0,  uint256 Q0)
    {
        uint256 denominator = DecimalMath.mul(DecimalMath.ONE.mul(2), DecimalMath.ONE.add(k.sqrt()));
        uint256 edgePrice = DecimalMath.divCeil(Q1, denominator);
        require(k < edgePrice, "Unable to long under current pool status!");
        uint256 ideltaB = DecimalMath.mul(deltaB, price);
        uint256 ac = ideltaB.mul(4).mul(Q1.sub(ideltaB).add(DecimalMath.mul(ideltaB,k)));
        uint256 square = (Q1.mul(Q1)).sub(ac);
        uint256 sqrt = square.sqrt();
        B0 = DecimalMath.divCeil(Q1.add(sqrt), price.mul(2));
        Q0 = DecimalMath.mul(B0, price);
    }

    /*
        Update BaseTarget when AMM holds long position
        given oracle price
        B0 == Q0 / price
    */
    function _RegressionTargetWhenLong(
        uint256 Q1,
        uint256 price,
        uint256 deltaB,
        uint256 k
    )
       internal pure returns (uint256 B0, uint256 Q0)
    {
        uint256 square = Q1.mul(Q1).add(DecimalMath.mul(deltaB, price).mul(DecimalMath.mul(Q1, k).mul(4)));
        uint256 sqrt = square.sqrt();
        uint256 deltaQ = DecimalMath.divCeil(sqrt.sub(Q1), k.mul(2));
        Q0 = Q1.add(deltaQ);
        B0 = DecimalMath.divCeil(Q0, price);
    }
}
