# Decentralized Stable Coin (DSC)

A decentralized stablecoin system built on Ethereum, designed to maintain a 1 DSC = $1 peg through overcollateralization with exogenous assets like ETH and BTC. This project implements an algorithmically stable, dollar-pegged stablecoin similar to DAI but without governance or fees, backed solely by wETH and wBTC.

## Features

- **Exogenous Collateral**: Backed by external assets (ETH & BTC) via Chainlink price feeds.
- **Dollar Pegged**: Maintains stability through algorithmic mechanisms.
- **Overcollateralized**: Requires 200% collateralization to ensure solvency.
- **Liquidation Mechanism**: Allows liquidation of undercollateralized positions with bonuses.
- **ERC20 Compliant**: DSC token inherits from OpenZeppelin's ERC20Burnable.

## Architecture

### Core Contracts

- **DSCEngine.sol**: Handles all logic for depositing collateral, minting/burning DSC, redeeming collateral, and liquidations. Integrates with Chainlink oracles for price data.
- **DecentralizedStableCoin.sol**: The ERC20 stablecoin token, mintable and burnable only by the DSCEngine.

### Libraries

- **OracleLib.sol**: Library for safe price feed interactions, including staleness checks.

### Scripts

- **DeployDSC.s.sol**: Deployment script for the DSC system.
- **HelperConfig.s.sol**: Configuration helper for network-specific settings (e.g., Sepolia, Anvil).

### Tests

- **Unit Tests**: Comprehensive tests for individual functions in `test/unit/`.
- **Fuzz Tests**: Invariant and handler-based fuzzing in `test/fuzz/` to ensure system robustness.
- **Mocks**: Mock contracts for testing (e.g., MockV3Aggregator).

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.
- Node.js (optional, for additional tooling).

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd stablecoin
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Build the project:
   ```bash
   forge build
   ```

### Setup

- For local development, use Anvil (Foundry's local Ethereum node):
  ```bash
  anvil
  ```

- Configure networks in `HelperConfig.s.sol` for Sepolia or other testnets.

## Usage

### Deployment

Run the deployment script:
```bash
forge script script/DeployDSC.s.sol --rpc-url <your-rpc-url> --private-key <your-private-key> --broadcast
```

This deploys the DSC and DSCEngine contracts, transferring ownership of DSC to DSCEngine.

### Interacting with the System

- **Deposit Collateral & Mint DSC**: Use `depositCollateralAndMintDsc()` in DSCEngine.
- **Redeem Collateral**: Use `redeemCollateral()` after burning DSC.
- **Liquidate**: Call `liquidate()` on undercollateralized positions.

Ensure to approve token transfers before calling functions.

## Testing

Run unit tests:
```bash
forge test
```

Run fuzz tests:
```bash
forge test --match-path test/fuzz
```

For invariant testing:
```bash
forge test --match-contract InvariantsTest
```

## Contributing

Contributions are welcome! Please ensure all tests pass and follow Solidity best practices. Open issues for bugs or feature requests.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
