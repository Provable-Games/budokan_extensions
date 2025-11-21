import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Upload, Plus, Trash2, FileUp } from "lucide-react";
import { type Entry } from "@/utils/contracts";

interface EntryManagerProps {
  onUpload: (entries: Entry[]) => Promise<void>;
  isUploading?: boolean;
  title?: string;
  description?: string;
}

export function EntryManager({
  onUpload,
  isUploading = false,
  title = "Add Entries",
  description = "Upload player addresses and their entry counts"
}: EntryManagerProps) {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [newAddress, setNewAddress] = useState("");
  const [newCount, setNewCount] = useState("");
  const [csvContent, setCsvContent] = useState("");

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

    setEntries([...entries, ...parsedEntries]);
    setCsvContent("");
  };

  const handleUploadEntries = async () => {
    if (entries.length === 0) return;

    try {
      await onUpload(entries);
      // Clear entries after successful upload
      setEntries([]);
    } catch (error) {
      console.error("Error uploading entries:", error);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
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
          <div className="space-y-2">
            <h3 className="font-semibold text-sm">Entries to Add ({entries.length})</h3>
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
            <Button
              onClick={handleUploadEntries}
              disabled={isUploading}
              className="w-full"
            >
              {isUploading ? (
                "Uploading..."
              ) : (
                <>
                  <FileUp className="h-4 w-4 mr-2" />
                  Upload {entries.length} Entries
                </>
              )}
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}