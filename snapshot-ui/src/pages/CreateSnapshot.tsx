import { useState, useEffect } from "react";
import { useAccount, useContract, useSendTransaction } from "@starknet-react/core";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Upload, Plus, Trash2, FileUp } from "lucide-react";
import { SNAPSHOT_VALIDATOR_ABI, SNAPSHOT_VALIDATOR_ADDRESS, type Entry } from "@/utils/contracts";
import { useNavigate, useSearchParams } from "react-router-dom";
import { CallData } from "starknet";

export function CreateSnapshot() {
  const { account, address } = useAccount();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const existingSnapshotId = searchParams.get('snapshot');
  const [snapshotId, setSnapshotId] = useState<string | null>(existingSnapshotId);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [newAddress, setNewAddress] = useState("");
  const [newCount, setNewCount] = useState("");
  const [csvContent, setCsvContent] = useState("");
  const [isCreating, setIsCreating] = useState(false);
  const [isUploading, setIsUploading] = useState(false);

  useEffect(() => {
    if (existingSnapshotId) {
      setSnapshotId(existingSnapshotId);
    }
  }, [existingSnapshotId]);

  const { contract } = useContract({
    address: SNAPSHOT_VALIDATOR_ADDRESS,
    abi: SNAPSHOT_VALIDATOR_ABI,
  });

  const { send: sendTransaction, isPending } = useSendTransaction({});

  const handleCreateSnapshot = async () => {
    if (!account) return;

    setIsCreating(true);
    try {
      const calls = {
        contractAddress: SNAPSHOT_VALIDATOR_ADDRESS,
        entrypoint: "create_snapshot",
        calldata: []
      };

      const result = await sendTransaction([calls]);

      // In a real app, you would parse the transaction result to get the snapshot ID
      // For now, we'll use a timestamp as a mock ID
      // TODO: Parse actual snapshot ID from transaction events
      const mockSnapshotId = Date.now().toString();
      setSnapshotId(mockSnapshotId);

    } catch (error) {
      console.error("Error creating snapshot:", error);
    } finally {
      setIsCreating(false);
    }
  };

  const handleAddEntry = () => {
    if (newAddress && newCount) {
      setEntries([...entries, { address: newAddress, count: parseInt(newCount) }]);
      setNewAddress("");
      setNewCount("");
    }
  };

  const handleRemoveEntry = (index: number) => {
    setEntries(entries.filter((_, i) => i !== index));
  };

  const handleParseCsv = () => {
    const lines = csvContent.trim().split("\n");
    const parsedEntries: Entry[] = [];

    for (const line of lines) {
      const [address, count] = line.split(",").map(s => s.trim());
      if (address && count) {
        parsedEntries.push({ address, count: parseInt(count) });
      }
    }

    setEntries(parsedEntries);
    setCsvContent("");
  };

  const handleUploadEntries = async () => {
    if (!account || !contract || !snapshotId || entries.length === 0) return;

    setIsUploading(true);
    try {
      // Format entries properly for the contract using CallData
      const calldata = CallData.compile({
        snapshot_id: snapshotId,
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

      // Navigate to view the snapshot
      navigate(`/snapshots/${snapshotId}`);
    } catch (error) {
      console.error("Error uploading entries:", error);
    } finally {
      setIsUploading(false);
    }
  };

  if (!address) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Connect Wallet</CardTitle>
          <CardDescription>
            Please connect your wallet to create snapshots
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">
          {existingSnapshotId ? 'Add Entries to Snapshot' : 'Create New Snapshot'}
        </h1>
        <p className="text-muted-foreground mt-2">
          {existingSnapshotId
            ? `Adding entries to snapshot ID: ${existingSnapshotId}`
            : 'Create a snapshot and upload player entry data'}
        </p>
      </div>

      {!snapshotId ? (
        <Card>
          <CardHeader>
            <CardTitle>Step 1: Initialize Snapshot</CardTitle>
            <CardDescription>
              Create a new snapshot ID to start uploading entries
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button
              onClick={handleCreateSnapshot}
              disabled={isCreating || !SNAPSHOT_VALIDATOR_ADDRESS}
              className="w-full"
            >
              {isCreating ? "Creating..." : "Create Snapshot"}
            </Button>
            {!SNAPSHOT_VALIDATOR_ADDRESS && (
              <p className="text-sm text-destructive mt-2">
                Contract address not configured. Please deploy the snapshot validator first.
              </p>
            )}
          </CardContent>
        </Card>
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle>Snapshot Created</CardTitle>
              <CardDescription>
                Snapshot ID: {snapshotId}
              </CardDescription>
            </CardHeader>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Step 2: Add Entries</CardTitle>
              <CardDescription>
                Add player addresses and their entry counts
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Tabs defaultValue="manual">
                <TabsList className="grid w-full grid-cols-2">
                  <TabsTrigger value="manual">Manual Entry</TabsTrigger>
                  <TabsTrigger value="csv">CSV Upload</TabsTrigger>
                </TabsList>

                <TabsContent value="manual" className="space-y-4">
                  <div className="flex gap-2">
                    <div className="flex-1">
                      <Label htmlFor="address">Address</Label>
                      <Input
                        id="address"
                        placeholder="0x..."
                        value={newAddress}
                        onChange={(e) => setNewAddress(e.target.value)}
                      />
                    </div>
                    <div className="w-32">
                      <Label htmlFor="count">Count</Label>
                      <Input
                        id="count"
                        type="number"
                        placeholder="1"
                        value={newCount}
                        onChange={(e) => setNewCount(e.target.value)}
                      />
                    </div>
                    <div className="flex items-end">
                      <Button onClick={handleAddEntry} size="icon">
                        <Plus className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                </TabsContent>

                <TabsContent value="csv" className="space-y-4">
                  <div>
                    <Label htmlFor="csv">CSV Data</Label>
                    <textarea
                      id="csv"
                      className="w-full h-32 px-3 py-2 text-sm rounded-md border border-input bg-background"
                      placeholder="address,count&#10;0x123...,5&#10;0x456...,3"
                      value={csvContent}
                      onChange={(e) => setCsvContent(e.target.value)}
                    />
                  </div>
                  <Button onClick={handleParseCsv} className="w-full">
                    <Upload className="h-4 w-4 mr-2" />
                    Parse CSV
                  </Button>
                </TabsContent>
              </Tabs>

              {entries.length > 0 && (
                <div className="mt-6 space-y-2">
                  <h3 className="font-semibold text-sm">Entries ({entries.length})</h3>
                  <div className="max-h-64 overflow-y-auto space-y-2">
                    {entries.map((entry, index) => (
                      <div key={index} className="flex items-center gap-2 p-2 border rounded">
                        <span className="flex-1 text-sm font-mono truncate">{entry.address}</span>
                        <span className="text-sm font-semibold">{entry.count}</span>
                        <Button
                          size="icon"
                          variant="ghost"
                          onClick={() => handleRemoveEntry(index)}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          {entries.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle>Step 3: Upload to Blockchain</CardTitle>
                <CardDescription>
                  Upload all entries to the snapshot contract
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Button
                  onClick={handleUploadEntries}
                  disabled={isUploading || isPending}
                  className="w-full"
                >
                  {isUploading || isPending ? (
                    "Uploading..."
                  ) : (
                    <>
                      <FileUp className="h-4 w-4 mr-2" />
                      Upload {entries.length} Entries
                    </>
                  )}
                </Button>
              </CardContent>
            </Card>
          )}
        </>
      )}
    </div>
  );
}