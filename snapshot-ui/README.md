# Snapshot Manager UI

A React application for managing snapshots for tournament entry validation on StarkNet.

## Features

- **Wallet Connection**: Connect using Argent, Braavos, or Cartridge Controller
- **Create Snapshots**: Initialize new snapshots with unique IDs
- **Upload Entries**: Add player addresses and entry counts via:
  - Manual entry form
  - CSV bulk upload
- **Lock Snapshots**: Make snapshots immutable once finalized
- **View Snapshots**: Browse and manage existing snapshots
- **Check Entries**: Verify player entry counts in snapshots

## Tech Stack

- **Frontend**: React 18 + TypeScript + Vite
- **Styling**: Tailwind CSS + Radix UI components
- **Blockchain**: StarkNet.js + starknet-react
- **Routing**: React Router v7

## Getting Started

### Prerequisites

- Node.js 20.19+ or 22.12+
- A StarkNet wallet (Argent, Braavos, or Cartridge Controller)

### Installation

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build
```

### Configuration

Before using the app, you need to deploy the snapshot validator contract and update the contract address in `src/utils/contracts.ts`:

```typescript
export const SNAPSHOT_VALIDATOR_ADDRESS = "0x..."; // Your deployed contract address
```

## Usage

### Creating a Snapshot

1. Connect your wallet
2. Navigate to "Create Snapshot"
3. Click "Create Snapshot" to generate a new snapshot ID
4. Add entries either:
   - **Manual Entry**: Enter addresses and counts one by one
   - **CSV Upload**: Paste CSV data in format: `address,count`
5. Click "Upload Entries" to save to blockchain

### Managing Snapshots

1. Navigate to "View Snapshots"
2. Enter a snapshot ID to view its details
3. Check the status (Created, InProgress, or Locked)
4. If you're the owner, you can lock the snapshot to prevent modifications
5. Check if specific addresses have entries in the snapshot

### Using Snapshots in Tournaments

Once a snapshot is locked, you can use its ID when creating tournaments on Budokan:
- The snapshot ID is passed in the extension configuration
- Players listed in the snapshot can enter tournaments
- Entry counts determine how many times a player can enter

## Project Structure

```
src/
├── components/
│   ├── ui/           # Reusable UI components
│   ├── Layout.tsx    # Main app layout
│   └── WalletConnect.tsx # Wallet connection component
├── pages/
│   ├── CreateSnapshot.tsx  # Snapshot creation page
│   ├── SnapshotManager.tsx # Home/dashboard page
│   └── ViewSnapshots.tsx   # View and manage snapshots
├── utils/
│   └── contracts.ts  # Contract ABI and configuration
├── lib/
│   └── utils.ts      # Utility functions
└── App.tsx           # Main app component with routing
```

## Contract Integration

The app interacts with the Snapshot Validator smart contract, which provides:

- `create_snapshot()`: Creates a new snapshot with unique ID
- `upload_snapshot_data()`: Uploads player entries to a snapshot
- `lock_snapshot()`: Locks a snapshot to prevent modifications
- `get_snapshot_metadata()`: Retrieves snapshot information
- `get_snapshot_entry()`: Checks player entry count
- `is_snapshot_locked()`: Verifies if snapshot is locked

## Development

```bash
# Run development server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview

# Lint code
npm run lint
```

## Deployment

The app can be deployed to any static hosting service:

1. Build the app: `npm run build`
2. Deploy the `dist` folder to your hosting service

Popular options:
- Vercel
- Netlify
- GitHub Pages
- IPFS

## License

MIT