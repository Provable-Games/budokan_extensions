import React, { useState, useEffect } from "react";
import { useParams } from "react-router-dom";
import {
  useAccount,
  useContract,
  useSendTransaction,
  useReadContract,
} from "@starknet-react/core";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Lock,
  Search,
  CheckCircle,
  Clock,
  AlertCircle,
  Plus,
} from "lucide-react";
import {
  SNAPSHOT_VALIDATOR_ABI,
  SNAPSHOT_VALIDATOR_ADDRESS,
  type SnapshotMetadata,
  type Entry,
} from "@/utils/contracts";
import { CallData } from "starknet";
import { EntryManager } from "@/components/EntryManager";
import { normalizeAddress, addressesEqual } from "@/utils/address";

export function ViewSnapshots() {
  const { id } = useParams();
  const { account, address } = useAccount();
  const [searchId, setSearchId] = useState(id || "");
  const [searchAddress, setSearchAddress] = useState("");
  const [entryCount, setEntryCount] = useState<number | null>(null);
  const [isLocking, setIsLocking] = useState(false);

  // States for adding entries
  const [showAddEntries, setShowAddEntries] = useState(false);
  const [isUploading, setIsUploading] = useState(false);

  const { contract } = useContract({
    address: SNAPSHOT_VALIDATOR_ADDRESS,
    abi: SNAPSHOT_VALIDATOR_ABI,
  });

  const { send: sendTransaction, isPending } = useSendTransaction({});

  // Read snapshot metadata
  const { data: metadataRaw, isLoading: isLoadingMetadata } = useReadContract({
    address: SNAPSHOT_VALIDATOR_ADDRESS,
    abi: SNAPSHOT_VALIDATOR_ABI,
    functionName: "get_snapshot_metadata",
    args: searchId ? [searchId] : undefined,
    watch: true,
  });

  console.log("Raw metadata:", metadataRaw);

  // Parse metadata from raw response
  const metadata: SnapshotMetadata | null = React.useMemo(() => {
    if (!metadataRaw) return null;

    console.log("Processing metadata:", metadataRaw);

    // Handle wrapped response
    let data = metadataRaw;

    // If wrapped in a metadata property
    if (typeof data === "object" && "metadata" in data) {
      data = data.metadata;
    }

    // Handle the CairoOption enum from the contract
    if (typeof data === "object" && data !== null) {
      // Check if it's a None variant
      if ("None" in data && data.None !== undefined) return null;

      // Handle Some variant (CairoOption)
      if ("Some" in data && data.Some) {
        const someData = data.Some;

        // Extract status value from CairoCustomEnum
        let status = someData.status;
        console.log("Raw status data:", status);
        console.log("Status type:", typeof status);
        console.log("Status keys:", status && typeof status === "object" ? Object.keys(status) : "not an object");

        // Handle different possible status structures
        if (status && typeof status === "object") {
          // Check for variant property (CairoCustomEnum structure)
          if ("variant" in status) {
            const variantName = Object.keys(status.variant)[0];
            status = variantName;
          }
          // Check for direct enum properties
          else if ("Created" in status || "InProgress" in status || "Locked" in status) {
            // Find which variant is present
            if ("Created" in status) status = "Created";
            else if ("InProgress" in status) status = "InProgress";
            else if ("Locked" in status) status = "Locked";
          }
          // Check for activeVariant or similar
          else if ("activeVariant" in status) {
            status = status.activeVariant;
          }
          // Check if it's a string-keyed object with the variant name
          else {
            const keys = Object.keys(status);
            if (keys.length === 1) {
              const key = keys[0];
              if (key === "Created" || key === "InProgress" || key === "Locked") {
                status = key;
              }
            }
          }
        }
        // If status is a string, it might already be the variant name
        else if (typeof status === "string") {
          // Status is already a string, use it as-is
          console.log("Status is already a string:", status);
        }
        // If status is a number, map it to the enum variant
        else if (typeof status === "number") {
          const statusMap = {
            0: "Created",
            1: "InProgress",
            2: "Locked"
          };
          status = statusMap[status] || status;
          console.log("Status was a number, mapped to:", status);
        }

        console.log("Parsed status:", status);

        // Convert and normalize owner address
        let owner = normalizeAddress(someData.owner);

        console.log("Parsed owner address:", owner);
        console.log("Current wallet address:", normalizeAddress(address));

        const parsedMetadata = {
          owner: owner,
          status: status
        } as SnapshotMetadata;

        console.log("Final parsed metadata:", parsedMetadata);
        return parsedMetadata;
      }

      // Direct metadata object (fallback)
      if ("owner" in data && "status" in data) {
        return data as SnapshotMetadata;
      }
    }

    return null;
  }, [metadataRaw]);

  // Read snapshot entry for a specific address
  const { data: entryData } = useReadContract({
    address: SNAPSHOT_VALIDATOR_ADDRESS,
    abi: SNAPSHOT_VALIDATOR_ABI,
    functionName: "get_snapshot_entry",
    args: searchId && searchAddress ? [searchId, searchAddress] : undefined,
  });

  useEffect(() => {
    if (entryData !== undefined) {
      setEntryCount(Number(entryData));
    }
  }, [entryData]);

  const handleLockSnapshot = async () => {
    if (!account || !searchId) return;

    setIsLocking(true);
    try {
      const calls = {
        contractAddress: SNAPSHOT_VALIDATOR_ADDRESS,
        entrypoint: "lock_snapshot",
        calldata: [searchId]
      };
      await sendTransaction([calls]);
    } catch (error) {
      console.error("Error locking snapshot:", error);
    } finally {
      setIsLocking(false);
    }
  };

  const handleSearchEntry = () => {
    // The useReadContract hook will automatically trigger when searchAddress changes
    // So we just need to update the state
  };

  const handleUploadEntries = async (entries: Entry[]) => {
    if (!account || !searchId || entries.length === 0) return;

    setIsUploading(true);
    try {
      // Format entries properly for the contract using CallData
      const calldata = CallData.compile({
        snapshot_id: searchId,
        snapshot_values: entries.map(entry => ({
          address: entry.address,
          count: entry.count.toString()
        }))
      });

      const calls = {
        contractAddress: SNAPSHOT_VALIDATOR_ADDRESS,
        entrypoint: "upload_snapshot_data",
        calldata: calldata
      };

      await sendTransaction([calls]);

      // Hide the form after successful upload
      setShowAddEntries(false);
    } catch (error) {
      console.error("Error uploading entries:", error);
      throw error; // Re-throw to let EntryManager handle it
    } finally {
      setIsUploading(false);
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case "Created":
        return <Clock className="h-4 w-4 text-blue-500" />;
      case "InProgress":
        return <AlertCircle className="h-4 w-4 text-yellow-500" />;
      case "Locked":
        return <CheckCircle className="h-4 w-4 text-green-500" />;
      default:
        return null;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case "Created":
        return "text-blue-500";
      case "InProgress":
        return "text-yellow-500";
      case "Locked":
        return "text-green-500";
      default:
        return "text-gray-500";
    }
  };

  if (!address) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Connect Wallet</CardTitle>
          <CardDescription>
            Please connect your wallet to view snapshots
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">View Snapshots</h1>
        <p className="text-muted-foreground mt-2">
          Search and manage your snapshots
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Search Snapshot</CardTitle>
          <CardDescription>
            Enter a snapshot ID to view its details
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label htmlFor="snapshot-id">Snapshot ID</Label>
            <div className="flex gap-2">
              <Input
                id="snapshot-id"
                type="number"
                placeholder="Enter snapshot ID"
                value={searchId}
                onChange={(e) => setSearchId(e.target.value)}
              />
              <Button disabled={!SNAPSHOT_VALIDATOR_ADDRESS}>
                <Search className="h-4 w-4 mr-2" />
                Search
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {searchId && metadata && (
        <>
          <Card>
            <CardHeader>
              <CardTitle>Snapshot Details</CardTitle>
              <CardDescription>ID: {searchId}</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                <div className="flex justify-between items-center">
                  <div>
                    <p className="text-sm text-muted-foreground">Owner</p>
                    <p className="font-mono text-sm">
                      {metadata.owner && typeof metadata.owner === "string"
                        ? `${metadata.owner.slice(
                            0,
                            6
                          )}...${metadata.owner.slice(-4)}`
                        : "Unknown"}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm text-muted-foreground">Status</p>
                    <div className="flex items-center gap-1 justify-end">
                      {getStatusIcon(metadata.status)}
                      <p
                        className={`font-semibold text-sm ${getStatusColor(
                          metadata.status
                        )}`}
                      >
                        {metadata.status}
                      </p>
                    </div>
                  </div>
                </div>

                {metadata.status !== "Locked" && addressesEqual(metadata.owner, address) && (
                  <div className="space-y-4">
                    <div className="flex gap-2">
                      <Button
                        onClick={() => setShowAddEntries(!showAddEntries)}
                        variant="outline"
                        className="flex-1"
                      >
                        {showAddEntries ? (
                          <>
                            <AlertCircle className="h-4 w-4 mr-2" />
                            Hide Entry Form
                          </>
                        ) : (
                          <>
                            <Plus className="h-4 w-4 mr-2" />
                            Add More Entries
                          </>
                        )}
                      </Button>
                      <Button
                        onClick={handleLockSnapshot}
                        disabled={isLocking || isPending}
                        variant="destructive"
                      >
                        {isLocking || isPending ? (
                          "Locking..."
                        ) : (
                          <>
                            <Lock className="h-4 w-4 mr-2" />
                            Lock Snapshot
                          </>
                        )}
                      </Button>
                    </div>
                    <div className="bg-yellow-50 dark:bg-yellow-950 border border-yellow-200 dark:border-yellow-800 rounded-md p-3">
                      <p className="text-sm text-yellow-800 dark:text-yellow-200">
                        This snapshot is still open. You can add more entries or
                        lock it to prevent modifications.
                      </p>
                    </div>
                  </div>
                )}

                {metadata.status === "Locked" && (
                  <div className="bg-green-50 dark:bg-green-950 border border-green-200 dark:border-green-800 rounded-md p-3">
                    <p className="text-sm text-green-800 dark:text-green-200">
                      This snapshot is locked and cannot be modified.
                    </p>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>

          {showAddEntries && metadata && metadata.status !== "Locked" && addressesEqual(metadata.owner, address) && (
            <EntryManager
              onUpload={handleUploadEntries}
              isUploading={isUploading || isPending}
              title="Add Entries to Snapshot"
              description="Upload more player addresses and their entry counts"
            />
          )}

          <Card>
            <CardHeader>
              <CardTitle>Check Entry</CardTitle>
              <CardDescription>
                Check if an address has entries in this snapshot
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <Label htmlFor="player-address">Player Address</Label>
                <div className="flex gap-2">
                  <Input
                    id="player-address"
                    placeholder="0x..."
                    value={searchAddress}
                    onChange={(e) => setSearchAddress(e.target.value)}
                  />
                  <Button onClick={handleSearchEntry}>
                    <Search className="h-4 w-4 mr-2" />
                    Check
                  </Button>
                </div>
              </div>

              {searchAddress && entryCount !== null && (
                <div className="bg-muted rounded-md p-4">
                  <p className="text-sm text-muted-foreground">Entry Count</p>
                  <p className="text-2xl font-bold">{entryCount}</p>
                  {entryCount > 0 ? (
                    <p className="text-sm text-green-600 dark:text-green-400 mt-1">
                      This address has {entryCount}{" "}
                      {entryCount === 1 ? "entry" : "entries"}
                    </p>
                  ) : (
                    <p className="text-sm text-red-600 dark:text-red-400 mt-1">
                      This address has no entries
                    </p>
                  )}
                </div>
              )}
            </CardContent>
          </Card>
        </>
      )}

      {searchId && isLoadingMetadata && (
        <Card>
          <CardContent className="py-8">
            <div className="text-center text-muted-foreground">
              Loading snapshot data...
            </div>
          </CardContent>
        </Card>
      )}

      {searchId && !isLoadingMetadata && !metadata && (
        <Card>
          <CardContent className="py-8">
            <div className="text-center text-muted-foreground">
              No snapshot found with ID: {searchId}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
