// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

// GitHub: quickswap-core/contracts/staking/StakingRewardsDualFactory.sol
// https://github.com/QuickSwap/quickswap-core/blob/5c0eb1b71477a2e9d46c6cd2aaec39628a086235/contracts/staking/StakingRewardsDualFactory.sol

interface IStakingDualRewards {
  // Views
  function lastTimeRewardApplicable() external view returns (uint256);

  function rewardPerTokenA() external view returns (uint256);

  function rewardPerTokenB() external view returns (uint256);

  function earnedA(address account) external view returns (uint256);

  function earnedB(address account) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  // Mutative

  function stake(uint256 amount) external;

  function withdraw(uint256 amount) external;

  function getReward() external;

  function exit() external;
}
