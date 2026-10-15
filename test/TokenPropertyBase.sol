// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./TestBase.sol";

abstract contract TokenPropertyBase is TestBase {
    // An independent oracle from the requested whole-token supply and decimals.
    uint256 internal constant EXPECTED_SUPPLY = 10_000_011 * 1e18;

    /// @dev Inclusive bounds, preserving inputs already in range. No discarded fuzz cases.
    function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
        require(minimum <= maximum, "invalid test bounds");
        if (value >= minimum && value <= maximum) return value;
        // The full uint256 interval always returns above, so this cannot overflow.
        return minimum + value % (maximum - minimum + 1);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
