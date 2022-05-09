// SPDX-License-Identifier: Gpl-3.0

pragma solidity 0.8.10;

import "../CelsiusxStrategy.sol";
import "../interfaces/idle/IIdleCDOStrategy.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/uniswapv2/IUniswapV2Factory.sol";
import "../interfaces/uniswapv2/IUniswapV2Router.sol";
import "./mocks/MockERC20.sol";
import "./mocks/StakingDualRewards.sol";

import "forge-std/test.sol";

contract CelsiusxStrategyTest is Test {
  uint256 internal constant POLYGON_MAINNET_CHIANID = 137;
  uint256 internal constant ONE_SCALE = 1e18;

  CelsiusxStrategy internal strategy;
  address internal underlying;
  address internal pool;

  address private constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
  address private constant CXETH = 0xfe4546feFe124F30788c4Cc1BB9AA6907A7987F9;

  address internal constant QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
  address internal constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

  address internal baseToken;
  address internal cxToken;

  address internal quick;
  address internal wmatic;
  address internal router = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;

  StakingDualRewards internal stakingRewards;

  address internal owner = address(0xBEEF);

  modifier runOnForkingNetwork(uint256 networkId) {
    // solhint-disable-next-line
    if (block.chainid == networkId) {
      _;
    }
  }

  function setUp() public virtual runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
    _setUp();

    strategy = new CelsiusxStrategy();
    strategy.initialize(
      address(strategy),
      underlying,
      baseToken,
      cxToken,
      owner,
      address(stakingRewards),
      router
    );

    // fund
    deal(underlying, address(this), 1e10, true);
    // deal(baseToken, address(this), ONE_SCALE, true);
    // deal(cxToken, address(this), ONE_SCALE, true);
    // // mint underlying token
    // IERC20(baseToken).transfer(underlying, ONE_SCALE);
    // IERC20(cxToken).transfer(underlying, ONE_SCALE);
    // IUniswapV2Pair(underlying).mint(address(this)); // add liquidity

    // set address(this) as idleCDO
    vm.prank(owner);
    strategy.setWhitelistedCDO(address(this));

    IERC20(underlying).approve(address(strategy), ONE_SCALE);

    /// label
    vm.label(address(strategy), "strategy");
    vm.label(underlying, "underlying");
    vm.label(baseToken, "baseToken");
    vm.label(cxToken, "cxToken");
    vm.label(router, "router");
  }

  function _setUp() internal virtual {
    // lpToken = deployCode("node_modules/@uniswap/v2-periphery", abi.encode(arg1, arg2));
    // underlying = 0xda7cd765DF426fCA6FB5E1438c78581E4e66bFe7; //  cxETH-ETH Pair
    // baseToken = WETH;
    // cxToken = CXETH;

    wmatic = address(new MockERC20("", ""));
    quick = address(new MockERC20("", ""));
    baseToken = address(new MockERC20("", ""));
    cxToken = address(new MockERC20("", ""));
    router = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    // create pair
    address pair = IUniswapV2Factory(IUniswapV2Router02(router).factory()).createPair(baseToken, cxToken); // prettier-ignore
    underlying = pair;

    /// pool setup
    deal(baseToken, pair, 100000 * ONE_SCALE, true);
    deal(cxToken, pair, 100000 * ONE_SCALE, true);
    vm.prank(address(0xfeed));
    IUniswapV2Pair(pair).mint(address(this)); // add liquidity

    /// staking reward setup
    stakingRewards = new StakingDualRewards(owner, owner, wmatic, quick, pair);
    deal(wmatic, address(stakingRewards), 100000 * ONE_SCALE, true);
    deal(quick, address(stakingRewards), 100000 * ONE_SCALE, true);
    vm.prank(owner);
    stakingRewards.notifyRewardAmount(
      100000 * ONE_SCALE,
      100000 * ONE_SCALE,
      1 weeks
    );
  }

  function testInitialize()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    strategy.initialize(
      address(strategy),
      underlying,
      baseToken,
      cxToken,
      owner,
      address(stakingRewards),
      router
    );

    assertEq(strategy.owner(), owner);
  }

  function testOnlyIdleCDOCanDepositOrRedeem()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    address caller = address(0xCAFE);
    vm.startPrank(caller);

    vm.expectRevert(CelsiusxStrategy.CelsiusxStrategy_OnlyIdleCDO.selector);
    strategy.deposit(1e10);

    vm.expectRevert(CelsiusxStrategy.CelsiusxStrategy_OnlyIdleCDO.selector);
    strategy.redeem(1e10);

    vm.expectRevert(CelsiusxStrategy.CelsiusxStrategy_OnlyIdleCDO.selector);
    strategy.redeemUnderlying(1e10);

    vm.expectRevert(CelsiusxStrategy.CelsiusxStrategy_OnlyIdleCDO.selector);
    strategy.redeemRewards(bytes(""));

    vm.stopPrank();
  }

  function testOnlyOwnerCanSweepTokens()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    deal(baseToken, address(strategy), 1e10);
    address caller = address(0xCAFE);
    vm.prank(caller);

    // sweep
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    strategy.transferToken(baseToken, 1e10, caller);
  }

  function testSweepTokens()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    // fund
    deal(baseToken, address(strategy), 1e10);
    // sweep
    vm.prank(owner);
    strategy.transferToken(baseToken, 1e10, address(0xbabe));
    assertEq(IERC20(baseToken).balanceOf(address(0xbabe)), 1e10);
  }

  function testSetWhiteListedCDO()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    // set whitelist
    vm.prank(owner);
    strategy.setWhitelistedCDO(address(0xbabe));
    assertEq(strategy.idleCDO(), address(0xbabe));

    vm.prank(owner);
    vm.expectRevert(bytes("IS_0"));
    strategy.setWhitelistedCDO(address(0));

    // only owner can set idleCDO
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    strategy.setWhitelistedCDO(address(0xbabe));
  }

  function testGetRewardTokens()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    address[] memory rewards = strategy.getRewardTokens();

    assertEq(rewards.length, 1);
    assertEq(rewards[0], QUICK);
  }

  function testDeposit() external runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
    strategy.deposit(1e10);

    assertEq(IERC20(underlying).balanceOf(address(this)), 0);
    assertEq(strategy.balanceOf(address(this)), 1e10); // price is equal to 1e18 in underlying
    assertEq(stakingRewards.balanceOf(address(strategy)), 1e10);
  }

  function testRedeem() external runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
    strategy.deposit(1e10);

    skip(1 days); // Skip 1 day forward

    strategy.redeem(1e10);

    assertEq(IERC20(underlying).balanceOf(address(this)), 1e10);
    assertEq(strategy.balanceOf(address(this)), 0);
    assertEq(stakingRewards.balanceOf(address(strategy)), 0);
    // get rewards
    assertGt(IERC20(wmatic).balanceOf(address(strategy)), 0);
    assertGt(IERC20(quick).balanceOf(address(strategy)), 0);
  }

  function testRedeemUnderlying()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    strategy.deposit(1e10);

    skip(1 days); // Skip 1 day forward

    strategy.redeemUnderlying(1e10);

    assertEq(IERC20(underlying).balanceOf(address(this)), 1e10);
    assertEq(strategy.balanceOf(address(this)), 0);
    assertEq(stakingRewards.balanceOf(address(strategy)), 0);
    // get rewards
    assertGt(IERC20(wmatic).balanceOf(address(strategy)), 0);
    assertGt(IERC20(quick).balanceOf(address(strategy)), 0);
  }

  // function testRedeemRewards()
  //   external
  //   runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  // {
  //   strategy.deposit(1e10);

  //   skip(7 days); // Skip 1 day forward

  //   uint256 quickRewards = stakingRewards.earnedB(address(strategy));
  //   uint256 _liquidityBefore = IUniswapV2Pair(underlying).balanceOf(
  //     address(stakingRewards)
  //   );
  //   uint256 _totalSupply = strategy.totalSupply();

  //   vm.prank(owner);
  //   uint256[] memory balances = strategy.redeemRewards(true);

  //   uint256 mintedLpTokens = IUniswapV2Pair(underlying).balanceOf(
  //     address(stakingRewards)
  //   ) - _liquidityBefore;

  //   // balances
  //   assertEq(
  //     stakingRewards.balanceOf(address(strategy)),
  //     1e10 + mintedLpTokens
  //   );
  //   assertEq(strategy.totalLpTokensStaked(), 1e10 + mintedLpTokens);

  //   // invariants
  //   assertEq(strategy.totalSupply(), _totalSupply);

  //   // rewards
  //   assertEq(balances.length, 2);
  //   assertEq(balances[0], mintedLpTokens);
  //   assertEq(balances[1], quickRewards);
  //   assertGt(IERC20(quick).balanceOf(owner), quickRewards);
  // }

  function testApr() external runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
    strategy.deposit(1e10);
    assertGt(strategy.getApr(), 0);
  }

  function testPrice() external runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
    // total supply is equal to zero
    assertEq(strategy.price(), ONE_SCALE);
    // total Lp tokens loced is equal to zero
    strategy.deposit(1e10);
    assertEq(strategy.price(), ONE_SCALE);
  }
}
