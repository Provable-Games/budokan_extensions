// Utility functions for handling StarkNet addresses

export function normalizeAddress(address: string | bigint | number | undefined | null): string {
  if (!address) return "";

  let hex: string;

  if (typeof address === "bigint") {
    hex = "0x" + address.toString(16);
  } else if (typeof address === "number") {
    hex = "0x" + address.toString(16);
  } else if (typeof address === "string") {
    // Remove any whitespace
    hex = address.trim();
    // If it doesn't start with 0x, add it
    if (!hex.startsWith("0x")) {
      hex = "0x" + hex;
    }
  } else {
    return "";
  }

  // Normalize to lowercase and ensure proper padding
  hex = hex.toLowerCase();

  // Pad to 64 characters (excluding 0x prefix)
  const paddedHex = "0x" + hex.slice(2).padStart(64, "0");

  return paddedHex;
}

export function addressesEqual(addr1: any, addr2: any): boolean {
  const normalized1 = normalizeAddress(addr1);
  const normalized2 = normalizeAddress(addr2);

  if (!normalized1 || !normalized2) return false;

  return normalized1 === normalized2;
}