// SPDX-License-Identifier: Gpl-3.0
pragma solidity 0.8.10;

import "./Integration.sol";

/// @title abstract contract for token integration test
/// @dev override `_setUp` function
contract ETHIntegrationTest is IntegrationTest {
  address private constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
  address private constant CXETH = 0xfe4546feFe124F30788c4Cc1BB9AA6907A7987F9;

  function _setUp() internal override {
    baseToken = WETH;
    cxToken = CXETH;
    underlying = 0xda7cd765DF426fCA6FB5E1438c78581E4e66bFe7;
    stakingRewards = StakingDualRewards(
      0xD8F0af6c455e09c44d134399eD1DF151043840E6
    );

    IntegrationTest._setUp();
  }
}
