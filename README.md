# Wave-Lite

A lightweight, gas-efficient smart contract for DAOs and open-source projects to run **Mini-Waves** — time-boxed contribution reward rounds with pro-rata ETH distribution based on points.

No governance token. No complex voting. Just: assign points, end the wave, contributors claim their share.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Contract Design](#contract-design)
- [Getting Started](#getting-started)
- [Deployment](#deployment)
- [Contract API](#contract-api)
- [Usage Walkthrough](#usage-walkthrough)
- [Security Model](#security-model)
- [Project Structure](#project-structure)

---

## Overview

Wave-Lite solves a common DAO problem: how do you fairly reward contributors for a sprint or milestone without complex infrastructure?

The flow is simple:

1. A **maintainer** deploys the contract with an ETH pool
2. As contributors complete work, the maintainer assigns them **points**
3. When the period ends, the maintainer calls `endWave()`
4. Contributors call `claim()` and receive their pro-rata share of the pool

```
Pool = 10 ETH
Alice = 70 points  →  claims 7 ETH
Bob   = 30 points  →  claims 3 ETH
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        Wave-Lite                        │
│                                                         │
│   Maintainer                                            │
│       │                                                 │
│       ├──── addPoints(alice, 70) ──────────────────┐    │
│       ├──── addPoints(bob, 30)   ──────────────────┤    │
│       │                                            ▼    │
│       └──── endWave() ──────► waveEnded = true          │
│                               totalPool = balance        │
│                                                         │
│   Contributors                                          │
│       │                                                 │
│       ├──── alice.claim() ──► share = 70/100 * pool     │
│       └──── bob.claim()   ──► share = 30/100 * pool     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### State Machine

```
         deploy()
            │
            ▼
     ┌─────────────┐
     │   OPEN      │  ◄── addPoints() allowed
     │  (active)   │
     └──────┬──────┘
            │ endWave()
            ▼
     ┌─────────────┐
     │   CLOSED    │  ◄── claim() allowed
     │  (ended)    │
     └─────────────┘
```

### Storage Layout

```
┌──────────────────────────────────────────────┐
│  Slot 0  │  maintainer (address, 20 bytes)   │
│  Slot 1  │  totalPoints (uint256)             │
│  Slot 2  │  totalPool (uint256)               │
│  Slot 3  │  waveEnded (bool, 1 byte)          │
│  Slot 4+ │  contributorPoints mapping         │
└──────────────────────────────────────────────┘
```

---

## Contract Design

### Full Source

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract WaveLite {
    address public maintainer;
    uint256 public totalPoints;
    uint256 public totalPool;
    bool public waveEnded;

    mapping(address => uint256) public contributorPoints;

    error OnlyMaintainer();
    error WaveAlreadyEnded();
    error WaveNotEnded();
    error NoPoints();
    error TransferFailed();

    event PointsAdded(address indexed contributor, uint256 points);
    event WaveClosed(uint256 totalPool, uint256 totalPoints);
    event Claimed(address indexed contributor, uint256 amount);

    constructor() payable {
        maintainer = msg.sender;
        totalPool = msg.value;
    }

    function addPoints(address contributor, uint256 points) external {
        if (msg.sender != maintainer) revert OnlyMaintainer();
        if (waveEnded) revert WaveAlreadyEnded();
        contributorPoints[contributor] += points;
        totalPoints += points;
        emit PointsAdded(contributor, points);
    }

    function endWave() external {
        if (msg.sender != maintainer) revert OnlyMaintainer();
        if (totalPoints == 0) revert NoPoints();
        totalPool = address(this).balance;
        waveEnded = true;
        emit WaveClosed(totalPool, totalPoints);
    }

    function claim() external {
        if (!waveEnded) revert WaveNotEnded();
        uint256 points = contributorPoints[msg.sender];
        if (points == 0) revert NoPoints();
        uint256 share = (points * totalPool) / totalPoints;
        contributorPoints[msg.sender] = 0;  // CEI: zero out before transfer
        (bool ok, ) = payable(msg.sender).call{value: share}("");
        if (!ok) revert TransferFailed();
        emit Claimed(msg.sender, share);
    }
}
```

### Pro-Rata Formula

```
share = (contributorPoints[msg.sender] * totalPool) / totalPoints
```

Integer division is safe here because `totalPool` is locked at `endWave()` time and all shares are calculated from the same snapshot.

---

## Getting Started

### Prerequisites

- Node.js >= 18
- npm

### Install

```bash
git clone <your-repo-url>
cd wave-lite
npm install
```

### Environment

Copy the example env file and fill in your values:

```bash
cp .env.example .env
```

```env
PRIVATE_KEY=your_wallet_private_key
RPC_URL=https://your-rpc-endpoint
```

### Compile

```bash
npm run compile
```

This outputs the ABI and bytecode to `artifacts/contracts/WaveLite.sol/WaveLite.json`.

---

## Deployment

### Local Hardhat Network

```bash
# Start a local node
npx hardhat node

# In a second terminal, deploy
npx hardhat run scripts/deploy.ts --network localhost
```

### Testnet / Mainnet

Update `hardhat.config.ts` with your network:

```typescript
import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    sepolia: {
      url: process.env.RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
};

export default config;
```

Then deploy:

```bash
npx hardhat run scripts/deploy.ts --network sepolia
```

---

## Contract API

### `constructor()` — `payable`

Deploys the contract and sets the caller as maintainer. Send ETH here to fund the pool.

```solidity
WaveLite wave = new WaveLite{value: 10 ether}();
```

---

### `addPoints(address contributor, uint256 points)`

Assigns points to a contributor. Only callable by the maintainer while the wave is open.

```solidity
wave.addPoints(0xAlice, 70);
wave.addPoints(0xBob, 30);
```

Reverts with `OnlyMaintainer` or `WaveAlreadyEnded` if conditions aren't met.

---

### `endWave()`

Closes the wave. Snapshots the current contract balance as `totalPool`. No more points can be added after this.

```solidity
wave.endWave();
```

Reverts with `NoPoints` if no points were assigned (prevents a zero-division scenario).

---

### `claim()`

Called by a contributor to withdraw their share. Uses the CEI pattern to prevent reentrancy.

```solidity
// Called by alice
wave.claim(); // receives (70 / 100) * 10 ETH = 7 ETH
```

Reverts with `WaveNotEnded` or `NoPoints` if conditions aren't met.

---

### Events

| Event | Emitted When |
|---|---|
| `PointsAdded(contributor, points)` | Maintainer assigns points |
| `WaveClosed(totalPool, totalPoints)` | Wave ends |
| `Claimed(contributor, amount)` | Contributor claims their share |

---

## Usage Walkthrough

Here's a full end-to-end example using ethers.js:

```typescript
import { ethers } from "ethers";
import WaveLiteABI from "./artifacts/contracts/WaveLite.sol/WaveLite.json";

const provider = new ethers.JsonRpcProvider("http://localhost:8545");
const maintainer = new ethers.Wallet(MAINTAINER_KEY, provider);
const alice = new ethers.Wallet(ALICE_KEY, provider);
const bob = new ethers.Wallet(BOB_KEY, provider);

// 1. Deploy with 10 ETH pool
const factory = new ethers.ContractFactory(
  WaveLiteABI.abi,
  WaveLiteABI.bytecode,
  maintainer
);
const wave = await factory.deploy({ value: ethers.parseEther("10") });
await wave.waitForDeployment();

// 2. Assign points
await wave.addPoints(alice.address, 70);
await wave.addPoints(bob.address, 30);

// 3. End the wave
await wave.endWave();

// 4. Contributors claim
await wave.connect(alice).claim(); // alice receives 7 ETH
await wave.connect(bob).claim();   // bob receives 3 ETH
```

---

## Security Model

| Property | Implementation |
|---|---|
| Reentrancy protection | CEI pattern — state zeroed before external call |
| Access control | `maintainer` address checked on write functions |
| Division by zero | `endWave()` reverts if `totalPoints == 0` |
| ETH transfer safety | Uses low-level `.call` instead of `.transfer` |
| Gas efficiency | Custom errors instead of `require` strings |

### Checks-Effects-Interactions in `claim()`

```solidity
// CHECK
uint256 points = contributorPoints[msg.sender];
if (points == 0) revert NoPoints();

// EFFECT — zero out before any external call
uint256 share = (points * totalPool) / totalPoints;
contributorPoints[msg.sender] = 0;

// INTERACT
(bool ok, ) = payable(msg.sender).call{value: share}("");
if (!ok) revert TransferFailed();
```

---

## Project Structure

```
wave-lite/
├── contracts/
│   └── WaveLite.sol          # Core contract
├── scripts/
│   └── deploy.ts             # Deployment script
├── test/                     # Test suite (add tests here)
├── artifacts/                # Compiled output (auto-generated)
├── hardhat.config.ts         # Hardhat configuration
├── tsconfig.json             # TypeScript config
├── package.json
└── .env.example              # Environment variable template
```

---

## License

MIT
