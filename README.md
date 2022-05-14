# Quickswap PYT

## Development

### Getting Started

This repo is based on https://github.com/libevm/forge-example

Install [forge](https://github.com/gakonst/foundry) to compile, test, and debug.

To install dependencies type:

```bash
forge install
```

To build Type:

```bash
forge build
```

### Test

To run on forking network copy `.env.example` to `.env` and setup api key.
Type:

```bash
# -vvv = very very verbose
forge test -f http://127.0.0.1:8545  --fork-block-number <FORK_BLOCK_NUMBER> -vvv
```

### Debugging

- access the debugger

```bash
forge run --debug src/test/Contract.t.sol --sig "testExample()"
```

## Contract Deployment

Copy `.env.example` to `.env` and fill it out with correct details.

```bash
node --experimental-json-modules scripts/deploy.js
```

## Etherscan Verification

Check here https://github.com/libevm/forge-example#etherscan-verification

## Docs

[Idle Finance docs](https://docs.idle.finance/developers/)
