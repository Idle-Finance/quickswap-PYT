// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UniswapV2Pool is ERC20("PoolMock", "") {
  function mint(address account, uint256 amount) external virtual {
    _mint(account, amount);
  }

  function burn(address account, uint256 amount) external virtual {
    _burn(account, amount);
  }
}
