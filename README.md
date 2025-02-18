# YapFun

YapFun Protocol is a decentralized derivatives platform for trading Kaito Yaps' mindshare. It enables users to take long or short positions on KOLs based on their "mindshare score" through a hybrid liquidity model combining order book matching and liquidity pools.

## Overview

The protocol consists of four main components:

1. **YapOracle**: An on-chain oracle system that maintains and updates KOL mindshare scores with staleness checks.
2. **YapOrderBook**: A hybrid trading infrastructure combining order book matching with liquidity pools.
3. **YapOrderBookFactory**: A factory contract for deploying new KOL-specific trading markets.
4. **YapEscrow**: An escrow contract that securely handles user funds and interacts with order books.

### Key Features

- **Hybrid Liquidity Model**

  - Primary order book matching for optimal price discovery.
  - Supplementary liquidity pool for instant execution.
  - 5% pool fee and 1% matching fee structure.

- **Position Management**

  - Long/Short positions on KOL mindshare scores.
  - Time-bound markets (3-day lifecycle).
  - Automated PnL calculation and settlement.
  - Real-time oracle price integration.

- **Role-Based Access Control**

  - Secure oracle data updates.
  - Protected market initialization.
  - Controlled liquidity provision.

- **Secure Fund Management**
  - Escrow-based fund handling ensures user balances are tracked and locked only when necessary.
  - Funds are transferred from escrow to order books upon fulfillment or locking.

## Technical Architecture

### YapOracle

- Maintains KOL data (rank, mindshare score, timestamps).
- Implements staleness checks (1-hour maximum delay).
- Uses OpenZeppelin's AccessControl for secure updates.
- Emits events for all data updates.

### YapOrderBook

- FIFO order matching system.
- Hybrid liquidity mechanism.
- Position tracking with unique identifiers.
- Automated PnL settlement.
- USDC as the settlement currency.

### YapOrderBookFactory

- Deploys new trading markets.
- Enforces 3-day trading lifecycle.
- Validates KOL IDs and oracle addresses.
- Emits events for market creation.

### YapEscrow

- Handles user deposits and tracks balances.
- Locks user funds for partially filled orders.
- Transfers funds to order books upon fulfillment.
- Ensures sufficient balances before fulfilling orders.
- Tracks locked balances for each user per market.

## Smart Contract Interaction Flow

1. Admin initializes a new market through YapOrderBookFactory.
2. Oracle updaters maintain current KOL data in YapOracle.
3. Users deposit funds into YapEscrow.
4. Traders can:
   - Open long/short positions.
   - Get matched through the order book.
   - Access pool liquidity when needed.
   - Close positions and settle PnL.
5. YapEscrow securely manages fund transfers between users and order books.

## Security Features

- Role-based access control for critical functions.
- Oracle staleness checks.
- Non-zero value validations.
- Safe math operations.
- Protected liquidity pool operations.
- Escrow-based fund management to prevent misuse of user funds.

## Fee Structure

- **Pool Fee**: 5% for liquidity pool usage.
- **Matching Fee**: 1% for order book matches.
- All fees contribute to the liquidity pool.

## Requirements

- Solidity ^0.8.24.
- OpenZeppelin Contracts (AccessControl, SafeERC20).
- USDC token for settlement.

## Development and Testing

```bash
# Install dependencies
forge install

# Run tests
forge test

# Deploy contracts
make deploy


```

## Disclaimer

- This protocol is in development and should be used with caution. Smart contracts may contain bugs and can result in the loss of funds.
- Ordebook is kinda retarted atm, need to find a better implementation.
