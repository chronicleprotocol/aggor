<img src="./assets/logo.png"/>

[![Unit Tests](https://github.com/chronicleprotocol/aggor/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/chronicleprotocol/aggor/actions/workflows/unit-tests.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Aggor is an oracle aggregator providing distributing trust among different oracle providers. For more info, see [docs/Aggor.md](./docs/Aggor.md).

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

Deployment via:

- [chronicleprotocol/greenhouse@v1](https://github.com/chronicleprotocol/greenhouse/tree/v1)
