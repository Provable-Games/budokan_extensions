import { Outlet, Link } from "react-router-dom";
import { WalletConnect } from "./WalletConnect";
import { Camera } from "lucide-react";

export function Layout() {
  return (
    <div className="min-h-screen bg-background">
      <header className="border-b">
        <div className="container mx-auto px-4 py-4">
          <nav className="flex items-center justify-between">
            <div className="flex items-center gap-6">
              <Link to="/" className="flex items-center gap-2 font-semibold text-lg">
                <Camera className="h-6 w-6" />
                Snapshot Manager
              </Link>
              <div className="flex items-center gap-4">
                <Link
                  to="/create"
                  className="text-sm text-muted-foreground hover:text-foreground transition-colors"
                >
                  Create Snapshot
                </Link>
                <Link
                  to="/snapshots"
                  className="text-sm text-muted-foreground hover:text-foreground transition-colors"
                >
                  View Snapshots
                </Link>
              </div>
            </div>
            <WalletConnect />
          </nav>
        </div>
      </header>
      <main className="container mx-auto px-4 py-8">
        <Outlet />
      </main>
    </div>
  );
}