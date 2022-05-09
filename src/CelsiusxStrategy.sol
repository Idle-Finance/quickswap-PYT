// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/idle/IIdleCDOStrategy.sol";
import "./interfaces/quickswap/IStakingDualRewards.sol";
import "./interfaces/uniswapv2/IUniswapV2Router.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "forge-std/console2.sol";

/// @author Idle Labs Inc.
/// @title IdleLidoStrategy
/// @notice IIdleCDOStrategy to deploy funds in Idle Finance
/// @dev This contract should not have any funds at the end of each tx.
/// The contract is upgradable, to add storage slots, add them after the last `###### End of storage VXX`
contract CelsiusxStrategy is
  Initializable,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  ERC20Upgradeable,
  IIdleCDOStrategy
{
  using SafeERC20 for IERC20;

  uint256 private constant ONE_SCALE = 1e18;
  /// @notice one year, used to calculate the APR
  uint256 public constant YEAR = 365 days;

  address private constant QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
  address private constant WBTC = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
  address private constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
  address private constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
  address private constant CXETH = 0xfe4546feFe124F30788c4Cc1BB9AA6907A7987F9;

  /// ###### Storage V1
  /// @notice address of the strategy used, in this case staked token
  address public override strategyToken;
  /// @notice underlying token address (LP token)
  address public override token;
  /// @notice one underlying token
  uint256 public override oneToken;
  /// @notice decimals of the underlying asset
  uint256 public override tokenDecimals;

  address public baseToken;

  address public cxToken;

  IStakingDualRewards public stakingRewards;

  /// @notice QuickSwap Router
  IUniswapV2Router02 public quickRouter;

  address public idleCDO;

  /// @notice amount last indexed for calculating APR
  uint256 public lastIndexAmount;

  /// @notice time when last deposit/redeem was made, used for calculating the APR
  uint256 public lastIndexedTime;

  /// @notice latest saved apr
  uint256 internal lastApr;

  /// @notice harvested tokens release delay
  uint256 public releaseBlocksPeriod = 6400; // ~24 hours

  /// @notice latest harvest
  uint256 public latestHarvestBlock;

  /// @notice total tokens staked
  uint256 public totalLpTokensStaked;

  /// @notice total tokens locked
  uint256 public totalLpTokensLocked;

  error CelsiusxStrategy_ReInitialized();

  error CelsiusxStrategy_OnlyIdleCDO();

  error CelsiusxStrategy_ZeroAddress();
  error CelsiusxStrategy_Decimals();

  /// ###### End of storage V1

  // Used to prevent initialization of the implementation contract
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    token = address(1);
  }

  // ###################
  // Initializer
  // ###################

  /// @notice can only be called once
  /// @dev Initialize the upgradable contract
  /// @param _strategyToken address of the strategy token
  /// @param _underlyingToken address of LP token
  /// @param _owner owner address
  function initialize(
    address _strategyToken,
    address _underlyingToken,
    address _baseToken,
    address _cxToken,
    address _owner,
    address _stakingRewards,
    address _router
  ) public initializer {
    // if (token != address(0)) revert CelsiusxStrategy_ReInitialized();
    // Initialize contracts
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    // Set basic parameters
    strategyToken = _strategyToken;
    token = _underlyingToken;
    baseToken = _baseToken;
    cxToken = _cxToken;
    lastIndexedTime = block.timestamp;

    tokenDecimals = IERC20Metadata(_underlyingToken).decimals();
    oneToken = 10**(tokenDecimals);
    if (oneToken != ONE_SCALE) revert CelsiusxStrategy_Decimals();

    stakingRewards = IStakingDualRewards(_stakingRewards);
    quickRouter = IUniswapV2Router02(_router);

    IERC20(_underlyingToken).safeApprove(_stakingRewards, type(uint256).max);

    // transfer ownership
    transferOwnership(_owner);
  }

  // ###################
  // Public methods
  // ###################

  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return shares strategyTokens minted
  function deposit(uint256 _amount)
    external
    override
    onlyIdleCDO
    returns (uint256 shares)
  {
    if (_amount != 0) {
      IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
      // deposit to a staking contract
      shares = _deposit(_amount);
      // mint shares
      _mint(msg.sender, shares);
    }
  }

  function _deposit(uint256 _amount) internal returns (uint256 shares) {
    _updateApr(int256(_amount));

    stakingRewards.stake(_amount);

    shares = (_amount * ONE_SCALE) / price();
    totalLpTokensStaked += _amount;
  }

  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
  /// @param _shares amount of strategyTokens to redeem
  /// @return amount of underlyings redeemed
  function redeem(uint256 _shares)
    external
    override
    onlyIdleCDO
    returns (uint256)
  {
    return _redeem(_shares);
  }

  /// @notice redeem the rewards. Claims all possible rewards
  function redeemRewards(bool claim)
    external
    onlyOwner
    returns (uint256[] memory balances)
  {
    balances = _redeemRewards(0, 0, 0, claim);
  }

  /// @notice redeem the rewards. Claims reward as per the _extraData
  /// @return balances amount of reward that is deposited to vault
  function redeemRewards(bytes calldata extraData)
    external
    override
    onlyIdleCDO
    returns (uint256[] memory balances)
  {
    (
      uint256 amountOutMin,
      uint256 amountBaseTokenMin,
      uint256 amountCxTokenMin,
      bool claim
    ) = abi.decode(extraData, (uint256, uint256, uint256, bool));

    balances = _redeemRewards(
      amountOutMin,
      amountBaseTokenMin,
      amountCxTokenMin,
      claim
    );
  }

  function _redeemRewards(
    uint256 amountOutMin,
    uint256 amountBaseTokenMin,
    uint256 amountCxTokenMin,
    bool claim
  ) internal returns (uint256[] memory balances) {
    IUniswapV2Router02 _router = quickRouter;
    address _baseToken = baseToken;
    address _cxToken = cxToken;

    // claim rewards
    if (claim) {
      stakingRewards.getReward();
    }

    // avold stack too deep error
    {
      // swap wmatic rewards for each token of the pool
      uint256 wmaticAmount = IERC20(WMATIC).balanceOf(address(this));
      _swap(WMATIC, _baseToken, wmaticAmount / 2, amountOutMin);
      _swap(WMATIC, _cxToken, wmaticAmount / 2, amountOutMin);
    }
    // get each balances
    uint256 amountBaseToken = IERC20(_baseToken).balanceOf(address(this));
    uint256 amountCxToken = IERC20(_cxToken).balanceOf(address(this));

    // add liquidity and mint Lp tokens
    _approveToken(_baseToken, address(_router), amountBaseToken);
    _approveToken(_cxToken, address(_router), amountCxToken);
    (, , uint256 mintedLpTokens) = _router.addLiquidity(
      _baseToken,
      _cxToken,
      amountBaseToken,
      amountCxToken,
      amountBaseTokenMin,
      amountCxTokenMin,
      address(this),
      block.timestamp
    );

    // deposit the minted lp tokens to a staking contract
    _deposit(mintedLpTokens);

    // save the block in which rewards are swapped and the amount
    latestHarvestBlock = block.number;
    totalLpTokensLocked = mintedLpTokens;

    balances = new uint256[](2); // [minted Lp tokens, Quick rewards]
    balances[0] = mintedLpTokens;
    balances[1] = IERC20(QUICK).balanceOf(address(this));

    // send Quick rewards to msg.sender
    IERC20(QUICK).safeTransfer(msg.sender, balances[0]);
  }

  /// @dev msg.sender should approve this contract first
  /// to spend `_amount * ONE_STETH_TOKEN / price()` of `strategyToken`
  /// @param _amount amount of underlying tokens to redeem
  /// @return amount of underlyings redeemed
  function redeemUnderlying(uint256 _amount)
    external
    override
    onlyIdleCDO
    returns (uint256)
  {
    return _redeem((_amount * ONE_SCALE) / price());
  }

  // ###################
  // Internal
  // ###################

  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
  /// @param _shares amount of strategyTokens to redeem
  /// @return redeemed amount of underlyings redeemed
  function _redeem(uint256 _shares) internal returns (uint256 redeemed) {
    if (_shares != 0) {
      redeemed = (_shares * price()) / ONE_SCALE;
      _updateApr(-int256(redeemed));

      _burn(msg.sender, _shares);

      totalLpTokensStaked -= redeemed;

      stakingRewards.withdraw(redeemed);
      stakingRewards.getReward();

      IERC20(token).safeTransfer(msg.sender, redeemed);
    }
  }

  /// @notice update last saved apr
  /// @param _amount amount of underlying tokens to mint/redeem
  function _updateApr(int256 _amount) internal {
    uint256 lptStaked = stakingRewards.balanceOf(address(this));
    // uint256 lptStaked = totalLpTokensStaked;
    uint256 _lastIndexAmount = lastIndexAmount;

    // console2.log("lptStaked :>>", lptStaked);
    // console2.log("_lastIndexAmount :>>", _lastIndexAmount);
    // console2.log("block.timestamp :>>", block.timestamp);
    // console2.log("lastIndexedTimee :>>", lastIndexedTime);

    if (_lastIndexAmount != 0) {
      uint256 gainPerc = ((lptStaked - _lastIndexAmount) * 10**20) / _lastIndexAmount; // prettier-ignore
      lastApr = (YEAR / (block.timestamp - lastIndexedTime)) * gainPerc;
    }
    lastIndexedTime = block.timestamp;
    lastIndexAmount = uint256(int256(lptStaked) + _amount);
    // console2.log("lastIndexAmount :>>", lastIndexAmount);
  }

  /// @notice Function to swap tokens on uniswapV2-fork DEX
  function _swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal returns (uint256 amountOut) {
    IUniswapV2Router02 _router = quickRouter;

    _approveToken(tokenIn, address(_router), amountIn);
    uint256[] memory amountOuts = _router.swapExactTokensForTokens(
      amountIn,
      minAmountOut,
      _getPath(tokenIn, tokenOut),
      address(this),
      block.timestamp
    );
    amountOut = amountOuts[amountOuts.length - 1];
  }

  // ###################
  // Views
  // ###################

  function _getPath(address tokenIn, address tokenOut)
    internal
    pure
    returns (address[] memory path)
  {
    require(tokenIn != tokenOut, "same-token");
    if (tokenIn != WETH && tokenOut != WETH) {
      path = new address[](3);
      path[0] = tokenIn;
      path[1] = WETH;
      path[2] = tokenOut;
    } else if (tokenIn == WETH) {
      path = new address[](2);
      path[0] = tokenIn;
      path[1] = tokenOut;
    }
  }

  /// @notice net price in underlyings of 1 strategyToken
  /// @return _price
  function price() public view override returns (uint256 _price) {
    uint256 _totalSupply = totalSupply();

    if (_totalSupply == 0) {
      _price = ONE_SCALE;
    } else {
      _price =
        ((totalLpTokensStaked - _lockedLpTokens()) * ONE_SCALE) /
        _totalSupply;
    }
  }

  function _lockedLpTokens() internal view returns (uint256 _locked) {
    uint256 _releaseBlocksPeriod = releaseBlocksPeriod;
    uint256 _blocksSinceLastHarvest = block.number - latestHarvestBlock;
    uint256 _totalLockedLpTokens = totalLpTokensLocked;

    if (
      _totalLockedLpTokens != 0 &&
      _blocksSinceLastHarvest < _releaseBlocksPeriod
    ) {
      // progressively release harvested rewards
      _locked = (_totalLockedLpTokens * (_releaseBlocksPeriod - _blocksSinceLastHarvest)) / _releaseBlocksPeriod; // prettier-ignore
    }
  }

  /// @return apr net apr (fees should already be excluded)
  function getApr() external view override returns (uint256 apr) {
    apr = lastApr;
  }

  /// @return tokens array of reward token addresses
  function getRewardTokens()
    external
    view
    override
    returns (address[] memory tokens)
  {
    tokens = new address[](1);
    tokens[0] = QUICK;
  }

  // ###################
  // Protected
  // ###################

  /// @notice Allow the CDO to pull stkAAVE rewards
  /// @return _bal amount of stkAAVE transferred
  function pullStkAAVE() external override returns (uint256 _bal) {}

  /// @notice This contract should not have funds at the end of each tx (except for stkAAVE), this method is just for leftovers
  /// @dev Emergency method
  /// @param _token address of the token to transfer
  /// @param value amount of `_token` to transfer
  /// @param _to receiver address
  function transferToken(
    address _token,
    uint256 value,
    address _to
  ) external onlyOwner nonReentrant {
    IERC20(_token).safeTransfer(_to, value);
  }

  /// @notice allow to update address whitelisted to pull stkAAVE rewards
  function setWhitelistedCDO(address _cdo) external onlyOwner {
    require(_cdo != address(0), "IS_0");
    idleCDO = _cdo;
  }

  /// @notice Modifier to make sure that caller os only the idleCDO contract
  modifier onlyIdleCDO() {
    if (idleCDO != msg.sender) revert CelsiusxStrategy_OnlyIdleCDO();
    _;
  }

  function _approveToken(
    address _token,
    address _spender,
    uint256 _allowance
  ) internal {
    IERC20(_token).safeApprove(_spender, 0);
    IERC20(_token).safeApprove(_spender, _allowance);
  }
}
