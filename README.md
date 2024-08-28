<img src="./assets/logo.png"/>

[![Unit Tests](https://github.com/chronicleprotocol/aggor/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/chronicleprotocol/aggor/actions/workflows/unit-tests.yml)

Aggor is an oracle aggregator distributing trust among different oracle providers. For more info, see [docs/Aggor.md](./docs/Aggor.md).

## Installation

Install module via Foundry:

```bash
$ forge install chronicleprotocol/aggor
```

## Contributing

The project uses the Foundry toolchain. You can find installation instructions [here](https://getfoundry.sh/).

Setup:

```bash
$ git clone https://github.com/chronicleprotocol/aggor
$ cd aggor/
$ forge install
```

Run tests:

```bash
$ forge test
$ forge test -vvvv # Run with full stack traces
$ FOUNDRY_PROFILE=intense forge test # Run in intense mode
```

Lint:

```bash
$ forge fmt [--check]
```

## Dependencies

- [chronicleprotocol/chronicle-std@v2](https://github.com/chronicleprotocol/chronicle-std/tree/v2)
- [uniswap/v3-periphery@0.8](https://github.com/Uniswap/v3-periphery/tree/0.8)
- [uniswap/v3-core@0.8](https://github.com/Uniswap/v3-core/tree/0.8)

## Licensing

The primary license for Aggor is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE). However, some files are dual licensed under `MIT`:

- All files in `src/libs/` may also be licensed under MIT (as indicated in their SPDX headers)
- Several Solidity interface files may also be licensed under `MIT` (as indicated in their SPDX headers)
- Several files in `script/` and `test/` may also be licensed under `MIT` (as indicated in their SPDX headers)
