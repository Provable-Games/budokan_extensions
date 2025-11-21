#!/usr/bin/env node
/**
 * Process delegate votes CSV and calculate entries based on vote thresholds.
 *
 * Configuration:
 * - Minimum votes: 100 (gets 3 entries)
 * - Maximum votes: 50,000 (gets maximum entries)
 * - Linear scaling between min and max
 */

const fs = require('fs');
const path = require('path');
const { parse } = require('csv-parse/sync');

// Configuration
const CONFIG = {
  minVotes: 100,
  maxVotes: 50000,
  minEntries: 3,
  maxEntries: 100, // You can adjust this - what should be the max entries for 50k votes?
};

/**
 * Calculate number of entries based on vote count.
 * Uses linear interpolation between min and max thresholds.
 *
 * @param {number} votes - Number of votes the delegate has
 * @returns {number} - Number of entries (0 if below threshold)
 */
function calculateEntries(votes) {
  if (votes < CONFIG.minVotes) {
    return 0;
  }

  if (votes >= CONFIG.maxVotes) {
    return CONFIG.maxEntries;
  }

  // Linear interpolation between min and max
  const voteRange = CONFIG.maxVotes - CONFIG.minVotes;
  const entryRange = CONFIG.maxEntries - CONFIG.minEntries;
  const votesAboveMin = votes - CONFIG.minVotes;

  const entries = CONFIG.minEntries + (votesAboveMin / voteRange) * entryRange;

  // Round to nearest integer
  return Math.round(entries);
}

/**
 * Read CSV file and process delegate votes into entries.
 *
 * @param {string} csvFilePath - Path to the CSV file
 * @returns {Array<{address: string, entries: number, votes: number}>}
 */
function processDelegateVotes(csvFilePath) {
  try {
    // Read CSV file
    const csvContent = fs.readFileSync(csvFilePath, 'utf-8');

    // Parse CSV
    const records = parse(csvContent, {
      columns: true,
      skip_empty_lines: true,
    });

    console.log(`Loaded ${records.length} records from CSV`);

    // Process each record
    const results = records
      .map((record) => {
        // Get the decimal vote count (already converted from wei in Python script)
        const votes = parseFloat(record.current_votes_decimal || '0');
        const address = record.delegate_hex;

        // Calculate entries
        const entries = calculateEntries(votes);

        return {
          address,
          entries,
          votes,
        };
      })
      // Filter out delegates with 0 entries (below minimum threshold)
      .filter((item) => item.entries > 0)
      // Sort by entries (descending) for easier review
      .sort((a, b) => b.entries - a.entries);

    return results;
  } catch (error) {
    console.error('Error processing CSV:', error.message);
    throw error;
  }
}

/**
 * Generate statistics about the processed data.
 *
 * @param {Array} results - Processed delegate entries
 * @returns {Object} - Statistics object
 */
function generateStats(results) {
  const totalEntries = results.reduce((sum, item) => sum + item.entries, 0);
  const totalDelegates = results.length;
  const avgEntries = totalDelegates > 0 ? totalEntries / totalDelegates : 0;

  const maxEntriesDelegate = results[0]; // Already sorted descending
  const minEntriesDelegate = results[results.length - 1];

  return {
    totalDelegates,
    totalEntries,
    avgEntries: Math.round(avgEntries * 100) / 100,
    maxEntriesDelegate: {
      address: maxEntriesDelegate?.address,
      entries: maxEntriesDelegate?.entries,
      votes: maxEntriesDelegate?.votes,
    },
    minEntriesDelegate: {
      address: minEntriesDelegate?.address,
      entries: minEntriesDelegate?.entries,
      votes: minEntriesDelegate?.votes,
    },
  };
}

/**
 * Main function
 */
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error('Usage: node process_delegate_entries.js <csv_file> [output_file]');
    console.error('\nExamples:');
    console.error('  node process_delegate_entries.js delegate_votes.csv');
    console.error('  node process_delegate_entries.js delegate_votes.csv entries.json');
    console.error('\nConfiguration:');
    console.error(`  Min votes: ${CONFIG.minVotes} (${CONFIG.minEntries} entries)`);
    console.error(`  Max votes: ${CONFIG.maxVotes} (${CONFIG.maxEntries} entries)`);
    process.exit(1);
  }

  const csvFilePath = path.resolve(args[0]);
  const outputFilePath = args[1]
    ? path.resolve(args[1])
    : path.resolve(`delegate_entries_${Date.now()}.json`);

  // Check if CSV file exists
  if (!fs.existsSync(csvFilePath)) {
    console.error(`Error: CSV file not found: ${csvFilePath}`);
    process.exit(1);
  }

  console.log('Processing Configuration:');
  console.log(`  Min votes: ${CONFIG.minVotes} → ${CONFIG.minEntries} entries`);
  console.log(`  Max votes: ${CONFIG.maxVotes} → ${CONFIG.maxEntries} entries`);
  console.log('');

  // Process the CSV
  const results = processDelegateVotes(csvFilePath);

  // Generate statistics
  const stats = generateStats(results);

  // Display statistics
  console.log('\n=== Statistics ===');
  console.log(`Total delegates with entries: ${stats.totalDelegates}`);
  console.log(`Total entries allocated: ${stats.totalEntries}`);
  console.log(`Average entries per delegate: ${stats.avgEntries}`);
  console.log('\nTop delegate:');
  console.log(`  Address: ${stats.maxEntriesDelegate.address}`);
  console.log(`  Votes: ${stats.maxEntriesDelegate.votes.toLocaleString()}`);
  console.log(`  Entries: ${stats.maxEntriesDelegate.entries}`);
  console.log('\nBottom delegate (min threshold):');
  console.log(`  Address: ${stats.minEntriesDelegate.address}`);
  console.log(`  Votes: ${stats.minEntriesDelegate.votes.toLocaleString()}`);
  console.log(`  Entries: ${stats.minEntriesDelegate.entries}`);

  // Save to JSON file
  const output = {
    config: CONFIG,
    generatedAt: new Date().toISOString(),
    stats,
    delegates: results,
  };

  fs.writeFileSync(outputFilePath, JSON.stringify(output, null, 2));
  console.log(`\nResults saved to: ${outputFilePath}`);

  // Also create a simple version with just address and entries
  const simpleOutput = results.map(({ address, entries }) => ({
    address,
    entries,
  }));

  const simpleFilePath = outputFilePath.replace('.json', '_simple.json');
  fs.writeFileSync(simpleFilePath, JSON.stringify(simpleOutput, null, 2));
  console.log(`Simple format saved to: ${simpleFilePath}`);
}

// Export for use as a module
if (require.main === module) {
  main();
} else {
  module.exports = {
    processDelegateVotes,
    calculateEntries,
    generateStats,
    CONFIG,
  };
}
