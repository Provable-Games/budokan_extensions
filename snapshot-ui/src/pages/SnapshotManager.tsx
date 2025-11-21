import { useAccount } from "@starknet-react/core";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Link } from "react-router-dom";
import { Plus, Eye, Lock } from "lucide-react";

export function SnapshotManager() {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh]">
        <Card className="w-full max-w-md">
          <CardHeader>
            <CardTitle>Welcome to Snapshot Manager</CardTitle>
            <CardDescription>
              Connect your wallet to manage snapshots for tournament entries
            </CardDescription>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground">
              Please connect your wallet using one of the options in the header to get started.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Snapshot Management</h1>
        <p className="text-muted-foreground mt-2">
          Create and manage snapshots for tournament entry validation
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Plus className="h-5 w-5" />
              Create Snapshot
            </CardTitle>
            <CardDescription>
              Start a new snapshot and upload player entries
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link to="/create">
              <Button className="w-full">Create New</Button>
            </Link>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Eye className="h-5 w-5" />
              View Snapshots
            </CardTitle>
            <CardDescription>
              Browse and manage your existing snapshots
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link to="/snapshots">
              <Button variant="outline" className="w-full">View All</Button>
            </Link>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Lock className="h-5 w-5" />
              Lock Snapshot
            </CardTitle>
            <CardDescription>
              Finalize a snapshot to make it immutable
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link to="/snapshots">
              <Button variant="secondary" className="w-full">Manage Locks</Button>
            </Link>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>How It Works</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold">
              1
            </div>
            <div>
              <h3 className="font-semibold">Create a Snapshot</h3>
              <p className="text-sm text-muted-foreground">
                Initialize a new snapshot with a unique ID
              </p>
            </div>
          </div>
          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold">
              2
            </div>
            <div>
              <h3 className="font-semibold">Upload Entries</h3>
              <p className="text-sm text-muted-foreground">
                Add player addresses and their entry counts via CSV or manual input
              </p>
            </div>
          </div>
          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold">
              3
            </div>
            <div>
              <h3 className="font-semibold">Lock Snapshot</h3>
              <p className="text-sm text-muted-foreground">
                Finalize the snapshot to prevent further modifications
              </p>
            </div>
          </div>
          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold">
              4
            </div>
            <div>
              <h3 className="font-semibold">Use in Tournaments</h3>
              <p className="text-sm text-muted-foreground">
                Reference the snapshot ID when creating tournaments on Budokan
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}