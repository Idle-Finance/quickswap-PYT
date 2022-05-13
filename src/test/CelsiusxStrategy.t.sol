// SPDX-License-Identifier: Gpl-3.0

pragma solidity 0.8.10;

import "../CelsiusxStrategy.sol";
import "../interfaces/idle/IIdleCDOStrategy.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/uniswapv2/IUniswapV2Factory.sol";
import "../interfaces/uniswapv2/IUniswapV2Router.sol";
import "./mocks/MockERC20.sol";
import "./mocks/StakingDualRewards.sol";

import "forge-std/Test.sol";

contract CelsiusxStrategyTest is Test {
  using stdStorage for StdStorage;

  uint256 internal constant POLYGON_MAINNET_CHIANID = 137;
  uint256 internal constant ONE_SCALE = 1e18;

  CelsiusxStrategy internal strategy;
  address internal underlying;
  address internal pool;

  address internal constant QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
  address internal constant DQUICK = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;
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

    // `token` is address(1) to prevent initialization of the implementation contract.
    // it need to be reset mannualy to test.
    strategy = new CelsiusxStrategy();
    stdstore
      .target(address(strategy))
      .sig(strategy.token.selector)
      .checked_write(address(0));
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
    wmatic = address(new MockERC20("", ""));
    quick = address(new MockERC20("", ""));
    baseToken = address(new MockERC20("", ""));
    cxToken = address(new MockERC20("", ""));
    // create pair
    address pair = IUniswapV2Factory(IUniswapV2Router02(router).factory())
      .createPair(baseToken, cxToken);
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

    assertEq(strategy.name(), "Idle Celsiusx Strategy Token");
    assertEq(
      strategy.symbol(),
      string(abi.encodePacked("idleCS", IERC20Metadata(underlying).symbol()))
    );
    assertEq(strategy.tokenDecimals(), 18);
    assertEq(address(strategy.stakingRewards()), address(stakingRewards));
    assertEq(address(strategy.quickRouter()), router);
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

  function testSetRouter()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    // set
    vm.prank(owner);
    strategy.setRouter(address(0xbabe));
    assertEq(address(strategy.quickRouter()), address(0xbabe));

    vm.prank(owner);
    vm.expectRevert(bytes("IS_0"));
    strategy.setRouter(address(0));

    // only owner can set idleCDO
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    strategy.setRouter(address(0xbabe));
  }

  function testSetReleaseBlocksPeriod()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    // set
    vm.prank(owner);
    strategy.setReleaseBlocksPeriod(1000);
    assertEq(strategy.releaseBlocksPeriod(), 1000);

    vm.prank(owner);
    vm.expectRevert(bytes("IS_0"));
    strategy.setReleaseBlocksPeriod(0);

    // only owner can set idleCDO
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    strategy.setReleaseBlocksPeriod(1000);
  }

  function testGetRewardTokens()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    address[] memory rewards = strategy.getRewardTokens();

    assertEq(rewards.length, 1);
    assertEq(rewards[0], DQUICK);
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
