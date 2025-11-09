# Disaster Relief Yield (DRY) - Donation DApp

A DeFi application that captures Uniswap V4 swap fees and accepts direct donations to support farmers affected by natural disasters. Built with Uniswap V4 hooks and Octant Protocol's ERC-4626 vault system.

## 🌟 Overview

DRY is a hackathon MVP that demonstrates innovative DeFi-for-good mechanisms:
- **Automatic Fee Capture**: 20% of Uniswap V4 swap fees go to disaster relief
- **Direct Donations**: Users can donate directly through the pool
- **Transparent Distribution**: Admin-triggered 50/50 distribution to verified farmers
- **Battle-tested Infrastructure**: Uses Octant's ERC-4626 vault for yield management

## 🏗️ Architecture

```
┌─────────────┐
│   Traders   │
└──────┬──────┘
       │ Swap
       ▼
┌─────────────────────────┐
│  Uniswap V4 Pool        │
│  + Custom Hook          │
└──────┬──────────────────┘
       │ 20% Fee Capture
       │ + Direct Donations
       ▼
┌─────────────────────────┐
│  Octant ERC-4626 Vault  │
│  (Yield Accumulation)   │
└──────┬──────────────────┘
       │ Yield Shares
       ▼
┌─────────────────────────┐
│  CalamityDistributor    │
│  (Smart Contract)       │
└──────┬──────────────────┘
       │ 50/50 Split
       ▼
┌─────────────────────────┐
│  Farmer 1   │  Farmer 2 │
└─────────────────────────┘
```

## 📦 Smart Contracts

### 1. FeeCaptureDonationHook.sol
**Hybrid Uniswap V4 Hook** - 5,396 bytes

**Features:**
- ✅ `afterSwap` hook - Captures 20% of swap fees automatically
- ✅ `afterDonate` hook - Accepts 100% of direct donations
- ✅ Deposits captured funds to Octant ERC-4626 vault
- ✅ Emits transparency events
- ✅ Gas-optimized for frequent calls

**Hook Permissions:**
```solidity
afterSwap: true      // Fee capture from swaps
afterDonate: true    // Accept direct donations
```

### 2. CalamityDistributor.sol
**Admin-Controlled Yield Distributor** - 3,072 bytes

**Features:**
- ✅ Receives ERC-4626 vault shares from Octant vault
- ✅ Redeems shares for underlying assets
- ✅ Distributes 50/50 to two farmer addresses
- ✅ Admin-only distribution trigger
- ✅ Emergency withdrawal mechanism
- ✅ Dynamic farmer address management

## 🧪 Testing

**Total: 40 tests, 100% passing ✅**

### CalamityDistributor Tests (21/21)
- Constructor validation
- Distribution logic (50/50 split)
- Farmer address management
- Emergency withdrawal
- View functions
- Fuzz testing

### FeeCaptureDonationHook Tests (19/19)
- Fee capture (20% calculation)
- Vault deposit integration
- Swap direction handling
- Donation acceptance
- Event emissions
- Access control
- Fuzz testing

**Run tests:**
```bash
forge test --summary
```

**Test coverage:**
```bash
forge coverage
```

## 🚀 Quick Start

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd DRY

# Install dependencies (already done via forge init)
forge install

# Build contracts
forge build

# Run tests
forge test

# Run tests with gas report
forge test --gas-report
```

### Local Testing with Mocks

```bash
# Deploy mock setup (ERC20 + ERC4626 vault + distributor)
forge script script/DeployMockSetup.s.sol --rpc-url http://localhost:8545 --broadcast
```

## 🌐 Deployment

### 1. Setup Environment Variables

```bash
cp .env.example .env
# Edit .env with your values
```

### 2. Deploy to Testnet

```bash
# Deploy all contracts
forge script script/Deploy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### 3. Verify Contracts

Contracts are automatically verified if you use `--verify` flag. Manual verification:

```bash
forge verify-contract <CONTRACT_ADDRESS> \
  src/CalamityDistributor.sol:CalamityDistributor \
  --chain-id 84532 \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" $VAULT $FARMER1 $FARMER2 $ADMIN)
```

## 📝 Configuration

### Environment Variables (.env)

```bash
# Network RPC
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc

# Private Keys
DEPLOYER_PRIVATE_KEY=0x...
ADMIN_PRIVATE_KEY=0x...

# Octant Vault
OCTANT_VAULT_ADDRESS=0x...

# Farmer Addresses
FARMER_1_ADDRESS=0x...
FARMER_2_ADDRESS=0x...

# Uniswap V4
POOL_MANAGER_ADDRESS=0x...
```

## 🎮 Usage Demo

### 1. Initial State
```
Vault Balance: 0
Farmer 1: 0 USDC
Farmer 2: 0 USDC
```

### 2. Trading Activity
- Users swap on Uniswap V4 pool
- Hook captures 20% of fees → deposits to vault
- Vault balance grows: 100 USDC → 500 USDC → 1000 USDC

### 3. Direct Donations (Optional)
- Whale donor calls `poolManager.donate(amount0, amount1)`
- Hook captures 100% of donation → deposits to vault
- Vault balance: +500 USDC from donation

### 4. Calamity Occurs
- Flood in Maharashtra affects farmers
- Admin calls: `distributor.distributeYield("Flood in Maharashtra")`

### 5. Final State
```
Vault Balance: 0 (distributed)
Farmer 1: 750 USDC (50%)
Farmer 2: 750 USDC (50%)
```

## 🛠️ Development

### Project Structure

```
DRY/
├── src/
│   ├── CalamityDistributor.sol       # Yield distributor
│   └── FeeCaptureDonationHook.sol    # Uniswap V4 hook
├── test/
│   ├── CalamityDistributor.t.sol     # Unit tests
│   ├── FeeCaptureDonationHook.t.sol  # Unit tests
│   └── mocks/                        # Mock contracts
│       ├── MockERC20.sol
│       ├── MockERC4626.sol
│       └── MockPoolManager.sol
├── script/
│   ├── Deploy.s.sol                  # Production deployment
│   └── DeployMockSetup.s.sol        # Local testing
├── foundry.toml                      # Foundry config
└── .env.example                      # Environment template
```

### Key Dependencies

- **Solidity**: ^0.8.24
- **Uniswap V4**: v4-core, v4-periphery
- **OpenZeppelin**: v5.0.0 (Ownable, SafeERC20, IERC4626)
- **Foundry**: forge-std

### Contract Sizes

| Contract | Size | Limit | Usage |
|----------|------|-------|-------|
| CalamityDistributor | 3,072 bytes | 24,576 bytes | 12.5% |
| FeeCaptureDonationHook | 5,396 bytes | 24,576 bytes | 22.0% |

## 🔐 Security Considerations

### Implemented
✅ OpenZeppelin's battle-tested contracts (Ownable, SafeERC20)
✅ Access control (only admin can distribute)
✅ Emergency withdrawal mechanism
✅ Event emissions for transparency
✅ Input validation (zero address checks)
✅ Reentrancy protection (via Checks-Effects-Interactions pattern)

### Recommendations for Production
⚠️ Professional security audit required
⚠️ Multi-sig for admin role
⚠️ Timelock for critical operations
⚠️ Oracle integration for disaster verification
⚠️ Token swap mechanism for non-vault assets
⚠️ Rate limiting on distributions

## 🌟 Future Enhancements

### Phase 2 - Governance
- [ ] Multi-farmer registration system
- [ ] Proof-of-farm verification (Chainlink oracles)
- [ ] DAO voting for distribution approval
- [ ] Multi-calamity queue system

### Phase 3 - Advanced Features
- [ ] ERC-4626 tokenized positions
- [ ] Cross-chain deployment (LayerZero)
- [ ] Frontend dashboard (React + wagmi)
- [ ] Automated disaster verification
- [ ] Dynamic fee adjustment based on market conditions

### Phase 4 - Ecosystem
- [ ] Integration with insurance protocols
- [ ] Staking rewards for vault depositors
- [ ] NFT certificates for donors
- [ ] Analytics dashboard

## 📚 Resources

### Uniswap V4
- [Official Docs](https://docs.uniswap.org/contracts/v4/overview)
- [Hook Examples](https://github.com/Uniswap/v4-periphery/tree/main/test/hooks)
- [V4 Template](https://github.com/Uniswap/v4-template)

### Octant Protocol
- [Octant Docs](https://docs.octant.app/)
- [Cantina Competition](https://cantina.xyz/competitions/917d796b-48d0-41d0-bb40-be137b7d3db5)
- [ERC-4626 Standard](https://erc4626.info/)

### Foundry
- [Foundry Book](https://book.getfoundry.sh/)
- [Testing Guide](https://book.getfoundry.sh/forge/tests)
- [Deployment Guide](https://book.getfoundry.sh/forge/deploying)

## 🤝 Contributing

This is a hackathon project. Contributions welcome!

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- **Uniswap Foundation** - V4 hooks architecture
- **Octant Protocol** - ERC-4626 vault inspiration
- **OpenZeppelin** - Secure contract libraries
- **Foundry** - Development framework

## ⚠️ Disclaimer

This is a hackathon MVP for demonstration purposes. NOT audited for production use. Use at your own risk.

---

**Built with ❤️ for disaster relief and Web3 innovation**
