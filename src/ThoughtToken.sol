// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PROOF OF THOUGHT
/// @notice Fixed-supply ERC-20. All tokens are minted once to the deploying caller.
contract ThoughtToken is ERC20 {
    /// @notice Entire supply in the token's smallest units (18 decimals).
    uint256 public constant INITIAL_SUPPLY = 10_000_011 * 10 ** 18;

    constructor() ERC20("PROOF OF THOUGHT", "THOUGHT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
