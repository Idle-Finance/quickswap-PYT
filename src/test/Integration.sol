// SPDX-License-Identifier: Gpl-3.0

pragma solidity 0.8.10;

import {IdleCDOPolygon, IdleCDOTranche} from "idle-tranches/contracts/polygon/IdleCDOPolygon.sol";
import {CelsiusxStrategy} from "../CelsiusxStrategy.sol";

import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/uniswapv2/IUniswapV2Factory.sol";
import "../interfaces/uniswapv2/IUniswapV2Router.sol";
import "./mocks/StakingDualRewards.sol";

import "forge-std/Test.sol";

abstract contract IntegrationTest is Test {
  using stdStorage for StdStorage;

  uint256 internal constant FULL_ALLOC = 100000;
  uint256 internal constant POLYGON_MAINNET_CHIANID = 137;
  uint256 internal constant ONE_SCALE = 1e18;

  address private constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
  address private constant QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
  address private constant DQUICK = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;
  address private constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
  address private constant WBTC = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;

  address internal constant router = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;

  address internal constant  owner = 0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6; // prettier-ignore
  address internal constant governanceFund = 0x1d60E17723f8Ca1F76F09126242AcD37a278b514; // prettier-ignore
  address internal constant rebalancer = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B; // prettier-ignore
  address internal constant multisig = 0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6; // prettier-ignore

  CelsiusxStrategy internal strategy;

  address internal underlying;

  address internal baseToken;
  address internal cxToken;

  StakingDualRewards internal stakingRewards;

  IdleCDOPolygon internal idleCDO;
  IdleCDOTranche internal AAtranche;
  IdleCDOTranche internal BBtranche;

  modifier runOnForkingNetwork(uint256 networkId) {
    // solhint-disable-next-line
    if (block.chainid == networkId) {
      _;
    }
  }

  function setUp() public virtual runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
    _setUp();

    // deploy strategy
    // `token` is address(1) to prevent initialization of the implementation contract.
    // it need to be reset mannualy.
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

    // deploy idleCDO and tranches
    address[] memory incentiveTokens = new address[](1);
    incentiveTokens[0] = QUICK;

    idleCDO = new IdleCDOPolygon();
    stdstore.target(address(idleCDO)).sig(idleCDO.token.selector).checked_write(
        address(0)
      );
    idleCDO.initialize(
      10000 * ONE_SCALE,
      underlying,
      governanceFund,
      owner,
      rebalancer,
      address(strategy),
      10000, // apr split: 100000 is 100% to AA
      50000, // ideal value: 50% AA and 50% BB tranches
      incentiveTokens
    );

    // get tranche ref
    AAtranche = IdleCDOTranche(idleCDO.AATranche());
    BBtranche = IdleCDOTranche(idleCDO.BBTranche());

    vm.prank(owner);
    strategy.setWhitelistedCDO(address(idleCDO));

    // fund
    deal(underlying, address(this), 1e10, true);

    IERC20(underlying).approve(address(idleCDO), type(uint256).max);

    /// label
    vm.label(address(idleCDO), "idleCDO");
    vm.label(address(AAtranche), "AAtranche");
    vm.label(address(BBtranche), "BBtranche");
    vm.label(address(strategy), "strategy");
    vm.label(underlying, "underlying");
    vm.label(baseToken, "baseToken");
    vm.label(cxToken, "cxToken");
    vm.label(router, "router");
    vm.label(address(stakingRewards), "stakingRewards");
    vm.label(WMATIC, "wmatic");
    vm.label(QUICK, "quick");
    vm.label(DQUICK, "dQuick");
  }

  function _setUp() internal virtual {
    assertEq(address(stakingRewards.rewardsTokenA()), DQUICK);
    assertEq(address(stakingRewards.rewardsTokenB()), WMATIC);
    assertGt(stakingRewards.rewardPerTokenA(), 0, "reward rateA");
    assertGt(stakingRewards.rewardPerTokenB(), 0, "reward rateB");
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
    assertEq(strategy.idleCDO(), address(idleCDO));
    assertEq(idleCDO.strategy(), address(strategy));
    assertEq(idleCDO.token(), underlying);
    assertEq(strategy.price(), 1e18);
    assertEq(idleCDO.tranchePrice(address(AAtranche)), 1e18);
    assertEq(idleCDO.tranchePrice(address(BBtranche)), 1e18);
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

  function testDepositAA()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    idleCDO.depositAA(1e10);

    assertEq(IERC20(AAtranche).balanceOf(address(this)), 1e10, "AATranche bal");
    assertEq(IERC20(underlying).balanceOf(address(this)), 0, "underlying bal");
    assertEq(strategy.balanceOf(address(idleCDO)), 0, "strategy bal");
    assertEq(stakingRewards.balanceOf(address(strategy)), 0);
  }

  function testDepositBB()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    idleCDO.depositBB(1e10);

    assertEq(IERC20(BBtranche).balanceOf(address(this)), 1e10, "BBtranche bal");
    assertEq(IERC20(underlying).balanceOf(address(this)), 0, "underlying bal");
    assertEq(strategy.balanceOf(address(idleCDO)), 0, "strategy bal");
    assertEq(stakingRewards.balanceOf(address(strategy)), 0);
  }

  function testRedeemAA()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    idleCDO.depositAA(1e10);

    // params
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](2);
    uint256[] memory _minAmount = new uint256[](2);
    uint256[] memory _sellAmounts = new uint256[](2);
    bytes memory _extraData = abi.encode(uint256(0), uint256(0), uint256(0));
    _skipFlags[3] = true;

    vm.prank(rebalancer);
    idleCDO.harvest(
      _skipFlags,
      _skipReward,
      _minAmount,
      _sellAmounts,
      _extraData
    );
    uint256 unlentPerc = 2000;
    uint256 unlentBal = (1e10 * unlentPerc) / FULL_ALLOC;
    assertEq(
      strategy.balanceOf(address(idleCDO)),
      1e10 - unlentBal,
      "strategy bal"
    );

    skip(180 days); // Skip 180 day forward
    vm.roll(block.number + 1); // Set block.height (newHeight)

    idleCDO.withdrawAA(1e10);

    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
    assertEq(
      IERC20(underlying).balanceOf(address(this)),
      1e10,
      "underlying bal"
    );
    assertEq(strategy.balanceOf(address(idleCDO)), 0, "strategy bal");

    assertEq(stakingRewards.balanceOf(address(strategy)), 0);

    // get rewards
    assertGt(IERC20(DQUICK).balanceOf(address(strategy)), 0);
    assertGt(IERC20(WMATIC).balanceOf(address(strategy)), 0);
  }

  // function testRedeemBB()
  //   external
  //   runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  // {
  //   idleCDO.depositBB(1e10);

  //   // params
  //   bool[] memory _skipFlags = new bool[](4);
  //   bool[] memory _skipReward = new bool[](2);
  //   uint256[] memory _minAmount = new uint256[](2);
  //   uint256[] memory _sellAmounts = new uint256[](2);
  //   bytes memory _extraData = abi.encode(uint256(0), uint256(0), uint256(0));
  //   _skipFlags[3] = true;

  //   vm.prank(rebalancer);
  //   idleCDO.harvest(
  //     _skipFlags,
  //     _skipReward,
  //     _minAmount,
  //     _sellAmounts,
  //     _extraData
  //   );

  //   uint256 unlentPerc = 2000;
  //   uint256 unlentBal = (1e10 * unlentPerc) / FULL_ALLOC;
  //   assertEq(
  //     strategy.balanceOf(address(idleCDO)),
  //     1e10 - unlentBal,
  //     "strategy bal"
  //   );

  //   skip(180 days); // Skip 180 day forward
  //   vm.roll(block.number + 1); // Set block.height (newHeight)

  //   idleCDO.withdrawBB(1e10);

  //   assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
  //   assertEq(
  //     IERC20(underlying).balanceOf(address(this)),
  //     1e10,
  //     "underlying bal"
  //   );
  //   assertEq(strategy.balanceOf(address(this)), 0, "strategy bal");
  //   assertEq(stakingRewards.balanceOf(address(strategy)), 0);

  //   // get rewards
  //   assertGt(IERC20(DQUICK).balanceOf(address(strategy)), 0);
  //   assertGt(IERC20(WMATIC).balanceOf(address(strategy)), 0);
  // }

  function testRedeemRewards()
    external
    runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  {
    idleCDO.depositAA(1e10);

    // params
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](2);
    uint256[] memory _minAmount = new uint256[](2);
    uint256[] memory _sellAmounts = new uint256[](2);
    bytes memory _extraData = abi.encode(uint256(0), uint256(0), uint256(0));
    _skipFlags[3] = false;

    vm.prank(rebalancer);
    idleCDO.harvest(
      _skipFlags,
      _skipReward,
      _minAmount,
      _sellAmounts,
      _extraData
    );

    skip(180 days); // Skip 180 day forward
    vm.roll(block.number + 1); // Set block.height (newHeight)

    uint256 quickRewards = stakingRewards.earnedB(address(strategy));
    uint256 _liquidityBefore = IUniswapV2Pair(underlying).balanceOf(
      address(stakingRewards)
    );
    uint256 _totalSupply = strategy.totalSupply();

    vm.prank(owner);
    uint256[] memory balances = strategy.redeemRewards();

    uint256 mintedLpTokens = IUniswapV2Pair(underlying).balanceOf(
      address(stakingRewards)
    ) - _liquidityBefore;

    // balances
    assertEq(
      stakingRewards.balanceOf(address(strategy)),
      1e10 + mintedLpTokens
    );
    assertEq(strategy.totalLpTokensStaked(), 1e10 + mintedLpTokens);

    // invariants
    assertEq(strategy.totalSupply(), _totalSupply);

    // rewards
    assertEq(balances.length, 2);
    assertEq(balances[0], mintedLpTokens);
    assertEq(balances[1], quickRewards);
    assertGt(IERC20(DQUICK).balanceOf(owner), quickRewards);
  }

  // function testHarvest() external runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
  //   deal(underlying, address(this), 10 * 1e10, true);
  //   idleCDO.depositAA(7e10);
  //   idleCDO.depositBB(3e10);

  //   deal(underlying, address(0xCAFE), 10e10, true);
  //   vm.prank(address(0xCAFE));
  //   idleCDO.depositAA(10e10);

  //   skip(7 days); // Skip 7 days forward

  //   uint256 quickRewards = stakingRewards.earnedB(address(strategy));
  //   uint256 _totalSupply = strategy.totalSupply();

  //   // params
  //   bool[] memory _skipFlags = new bool[](4);
  //   bool[] memory _skipReward = new bool[](2);
  //   uint256[] memory _minAmount = new uint256[](2);
  //   uint256[] memory _sellAmounts = new uint256[](2);
  //   bytes memory _extraData = abi.encode(uint256(0), uint256(0), uint256(0));
  //   //  index 0 : wmatic
  //   // _skipFlags[0] = false;
  //   // _skipReward[0] = true;
  //   // _minAmount[0] = 0;
  //   // _sellAmounts[0] = 0;

  //   // index 0 : quick
  //   _skipFlags[0] = true;
  //   _skipReward[0] = true;
  //   _minAmount[0] = 0;
  //   _sellAmounts[0] = 0;

  //   vm.prank(rebalancer);
  //   idleCDO.harvest(
  //     _skipFlags,
  //     _skipReward,
  //     _minAmount,
  //     _sellAmounts,
  //     _extraData
  //   );

  //   // balances
  //   assertGt(stakingRewards.balanceOf(address(strategy)), 20e10);
  //   assertGt(strategy.totalLpTokensStaked(), 20e10);

  //   // invariants
  //   assertEq(strategy.totalSupply(), _totalSupply);

  //   // rewards
  //   assertEq(IERC20(QUICK).balanceOf(address(idleCDO)), quickRewards);
  // }

  // function testSetStrategy()
  //   external
  //   runOnForkingNetwork(POLYGON_MAINNET_CHIANID)
  // {
  //   // fund
  //   deal(underlying, address(idleCDO), 2 * 1e10, true);

  //   CelsiusxStrategy _newStrategy = new CelsiusxStrategy();
  //   _newStrategy.initialize(
  //     address(strategy),
  //     underlying,
  //     baseToken,
  //     cxToken,
  //     owner,
  //     address(stakingRewards),
  //     router
  //   );
  //   address[] memory incentiveTokens = new address[](0);
  //   idleCDO.setStrategy(address(_newStrategy), incentiveTokens);

  //   assertEq(IERC20(BBtranche).balanceOf(address(this)), 0);
  //   assertEq(IERC20(underlying).balanceOf(address(this)), 1e10);
  //   assertEq(strategy.balanceOf(address(this)), 0);
  //   assertEq(stakingRewards.balanceOf(address(strategy)), 0);
  // }

  // function testApr() external runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
  //   strategy.deposit(1e10);
  //   assertGt(strategy.getApr(), 0);
  // }

  // function testPrice() external runOnForkingNetwork(POLYGON_MAINNET_CHIANID) {
  //   // total supply is equal to zero
  //   assertEq(strategy.price(), ONE_SCALE);
  //   // total Lp tokens loced is equal to zero
  //   strategy.deposit(1e10);
  //   assertEq(strategy.price(), ONE_SCALE);
  // }
}
