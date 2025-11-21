# Delegate Votes Entry Calculator

Scripts to query delegate votes from PostgREST API and calculate entry allocations based on voting power.

## Overview

This toolset consists of two scripts:

1. **`query_delegate_votes.py`** - Fetches delegate voting data from API and exports to CSV
2. **`process_delegate_entries.js`** - Processes CSV and calculates entry allocations

## Setup

### Python Script Setup
```bash
pip install -r requirements.txt
```

### Node.js Script Setup
```bash
npm install
```

## Usage

### Step 1: Query Delegate Votes

Fetch current delegate votes from the API and save to CSV:

```bash
# Run immediately
python query_delegate_votes.py

# Run with custom output filename
python query_delegate_votes.py -o votes.csv

# Schedule to run at specific time (24-hour format)
python query_delegate_votes.py -t 14:30

# Schedule with custom filename
python query_delegate_votes.py -t 09:00 -o morning_votes.csv
```

### Step 2: Calculate Entry Allocations

Process the CSV to calculate entries based on voting power:

```bash
# Process CSV file
node process_delegate_entries.js delegate_votes_*.csv

# Process with custom output filename
node process_delegate_entries.js votes.csv entries.json
```

## Configuration

### Entry Calculation Rules

Edit `process_delegate_entries.js` to adjust the `CONFIG` object:

```javascript
const CONFIG = {
  minVotes: 100,      // Minimum votes to qualify for entries
  maxVotes: 50000,    // Votes for maximum entries
  minEntries: 3,      // Entries given at minimum threshold
  maxEntries: 100,    // Entries given at maximum threshold
};
```

**Current settings:**
- Delegates with **< 100 votes**: 0 entries (excluded)
- Delegates with **100 votes**: 3 entries
- Delegates with **50,000+ votes**: 100 entries
- **Linear scaling** between thresholds

**Note:** Vote counts are automatically converted from wei (18 decimals) to standard units. The Python script handles this conversion when exporting to CSV.

## Output Files

### From Python Script
- `delegate_votes_YYYYMMDD_HHMMSS.csv` - Full voting data with fields:
  - `delegate` - Numeric delegate ID
  - `current_votes` - Vote count in wei (hexadecimal)
  - `delegate_hex` - Delegate address (hexadecimal)
  - `current_votes_decimal` - Vote count converted from wei to standard units (divided by 10^18)

### From Node.js Script
- `delegate_entries_*.json` - Full output with config, stats, and all delegate data
- `delegate_entries_*_simple.json` - Simplified format with just address and entries:
  ```json
  [
    {
      "address": "0x...",
      "entries": 45
    }
  ]
  ```

## Example Workflow

```bash
# 1. Fetch latest votes
python query_delegate_votes.py -o current_votes.csv

# 2. Calculate entries
node process_delegate_entries.js current_votes.csv allocations.json

# 3. Use the simple output for integration
cat allocations_simple.json
```

## API Endpoint

Default: `https://postgrest-production-148c.up.railway.app/current_delegate_votes_view`

Override with `--api-url` flag:
```bash
python query_delegate_votes.py --api-url https://custom-api.example.com
```
