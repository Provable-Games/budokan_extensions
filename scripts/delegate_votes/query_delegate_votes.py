#!/usr/bin/env python3
"""
Script to query delegate votes from PostgREST API and save to CSV.
Can be run immediately or scheduled for a specific time.
"""

import requests
import csv
import sys
from datetime import datetime
from pathlib import Path
import time
import argparse


def fetch_delegate_votes(api_url):
    """
    Fetch delegate votes from the API endpoint.

    Args:
        api_url: The base URL of the PostgREST API

    Returns:
        List of delegate vote records
    """
    endpoint = f"{api_url}/current_delegate_votes_view"

    try:
        print(f"Fetching data from {endpoint}...")
        response = requests.get(endpoint, timeout=30)
        response.raise_for_status()
        data = response.json()
        print(f"Successfully fetched {len(data)} records")
        return data
    except requests.exceptions.RequestException as e:
        print(f"Error fetching data: {e}", file=sys.stderr)
        sys.exit(1)


def convert_hex_to_decimal(hex_str):
    """Convert hexadecimal string to decimal, accounting for 18 decimals (wei)."""
    try:
        if hex_str.startswith('0x'):
            wei_value = int(hex_str, 16)
            # Convert from wei (18 decimals) to standard units
            return wei_value / (10 ** 18)
        return hex_str
    except (ValueError, AttributeError):
        return hex_str


def save_to_csv(data, output_file):
    """
    Save delegate votes data to CSV file.

    Args:
        data: List of delegate vote records
        output_file: Path to output CSV file
    """
    if not data:
        print("No data to save", file=sys.stderr)
        return

    # Get fieldnames from first record
    fieldnames = list(data[0].keys())

    # Add a converted votes column for easier reading
    fieldnames_extended = fieldnames + ['current_votes_decimal']

    try:
        with open(output_file, 'w', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames_extended)
            writer.writeheader()

            for row in data:
                # Create extended row with decimal conversion
                extended_row = row.copy()
                extended_row['current_votes_decimal'] = convert_hex_to_decimal(row.get('current_votes', '0x0'))
                writer.writerow(extended_row)

        print(f"Data successfully saved to {output_file}")
        print(f"Total records: {len(data)}")
    except IOError as e:
        print(f"Error writing to file: {e}", file=sys.stderr)
        sys.exit(1)


def wait_until_time(target_time_str):
    """
    Wait until a specific time to execute.

    Args:
        target_time_str: Time string in HH:MM format (24-hour)
    """
    try:
        target_hour, target_minute = map(int, target_time_str.split(':'))

        now = datetime.now()
        target = now.replace(hour=target_hour, minute=target_minute, second=0, microsecond=0)

        # If target time has passed today, schedule for tomorrow
        if target <= now:
            from datetime import timedelta
            target = target + timedelta(days=1)

        wait_seconds = (target - now).total_seconds()
        print(f"Current time: {now.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Scheduled to run at: {target.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Waiting {wait_seconds:.0f} seconds...")

        time.sleep(wait_seconds)
        print(f"Executing at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    except ValueError:
        print(f"Invalid time format: {target_time_str}. Use HH:MM (24-hour format)", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Query delegate votes and save to CSV',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run immediately with default output filename
  python query_delegate_votes.py

  # Run immediately with custom output filename
  python query_delegate_votes.py -o votes_2024.csv

  # Schedule to run at 14:30 (2:30 PM)
  python query_delegate_votes.py -t 14:30

  # Schedule to run at 9:00 AM with custom filename
  python query_delegate_votes.py -t 09:00 -o morning_votes.csv

  # Use custom API URL
  python query_delegate_votes.py --api-url https://custom-api.example.com
        """
    )

    parser.add_argument(
        '-o', '--output',
        default=f'delegate_votes_{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv',
        help='Output CSV filename (default: delegate_votes_YYYYMMDD_HHMMSS.csv)'
    )

    parser.add_argument(
        '-t', '--time',
        help='Schedule execution time in HH:MM format (24-hour). If not specified, runs immediately.'
    )

    parser.add_argument(
        '--api-url',
        default='https://postgrest-production-148c.up.railway.app',
        help='API base URL (default: https://postgrest-production-148c.up.railway.app)'
    )

    args = parser.parse_args()

    # If scheduled time is provided, wait until that time
    if args.time:
        wait_until_time(args.time)

    # Fetch and save data
    data = fetch_delegate_votes(args.api_url)
    save_to_csv(data, args.output)


if __name__ == '__main__':
    main()
