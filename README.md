# YapFun Protocol

YapFun is a decentralized trading platform that lets you trade on the social influence of Key Opinion Leaders (KOLs) from Kaito's ecosystem. Think of it like trading stocks, but instead of company shares, you're trading on how influential a KOL is based on their "mindshare score" - a metric that measures their social impact and engagement.

## What is Mindshare Score?

A mindshare score is a numerical value that represents a KOL's influence and engagement level in the Crypto Twitter. This score is calculated based on various factors like:

- Social engagement
- Content quality
- Community interaction
- Overall influence

The higher the score, the more influential the KOL is considered to be.

## How Does It Work?

1. **Trading Markets**: Each KOL has their own trading market that lasts for 3 days
2. **Position Types**:
   - Go LONG if you think their influence will increase
   - Go SHORT if you think their influence will decrease
3. **Trading**: Place orders through an order book system or use the liquidity pool for instant trades
4. **Settlement**: After 3 days, positions are settled based on the final mindshare score

All trades use USDC as the settlement currency, making it easy to understand your profits and losses in dollar terms.

## Core Components

### 1. Oracle System (YapOracle)

- Provides real-time mindshare scores
- Updates at least every hour
- Ensures data reliability through staleness checks

### 2. Order Book (YapOrderBook)

- Matches buy and sell orders
- Provides transparent price discovery
- Tracks all trading positions
- Handles automatic settlement at market expiry

### 3. Market Creation (YapOrderBookFactory)

- Creates new trading markets for KOLs
- Enforces the 3-day trading period
- Ensures proper market initialization

### 4. Fund Security (YapEscrow)

- Safely holds user funds
- Only locks funds when needed for trades
- Handles automatic profit/loss settlement

## Fees

The protocol charges minimal fees to maintain sustainability:

- 0.3% trading fee on matched orders
- All fees contribute to protocol maintenance and development

## For Developers

### Requirements

- Solidity ^0.8.17
- Foundry for development and testing
- OpenZeppelin contracts

### Quick Start

```bash
# Install dependencies
forge install

# Run tests
forge test

# Deploy contracts
make deploy
```

### Key Files

- `src/YapOrderBook.sol`: Main trading logic
- `src/YapEscrow.sol`: Fund management
- `src/YapOracle.sol`: Mindshare data management
- `src/YapOrderBookFactory.sol`: Market creation

## Security Considerations

The protocol implements several security measures:

- Role-based access control for administrative functions
- Hourly oracle updates with staleness checks
- Secure fund management through escrow
- Protected liquidity pool operations

## Current Status

This protocol is currently in development. While core functionality is implemented, we are actively:

- Optimizing the order matching system
- Enhancing liquidity mechanisms
- Implementing additional security measures
- Conducting thorough testing

## Disclaimer

This protocol is in active development and should be used with caution. Smart contracts inherently carry risks and may contain bugs that could result in loss of funds. Always do your own research and understand the risks before participating.
