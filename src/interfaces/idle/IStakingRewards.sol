// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakingRewards {
  /* ========== VIEWS ========== */
  function rewardsToken() external view returns (IERC20);

  function stakingToken() external view returns (IERC20);

  function rewardRate() external view returns (uint256);

  function rewardsDuration() external view returns (uint256);

  function lastUpdateTime() external view returns (uint256);

  function rewardPerTokenStored() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function lastTimeRewardApplicable() external view returns (uint256);

  function rewardPerToken() external view returns (uint256);

  function earned(address account) external view returns (uint256);

  function getRewardForDuration() external view returns (uint256);

  /* ========== MUTATIVE FUNCTIONS ========== */

  // Add stakeFor to allow IdleCDO to stake tranche tokens received as fees for the feeReceiver
  function stakeFor(address _user, uint256 amount) external;

  function stake(uint256 amount) external;

  function withdraw(uint256 amount) external;

  function getReward() external;

  function exit() external;
}
