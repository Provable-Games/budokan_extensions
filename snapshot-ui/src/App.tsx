import {
  StarknetConfig,
  jsonRpcProvider,
  voyager,
  InjectedConnector,
} from "@starknet-react/core";
import { mainnet, type Chain } from "@starknet-react/chains";
import { ControllerConnector } from "@cartridge/connector";
import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import { Layout } from "./components/Layout";
import { SnapshotManager } from "./pages/SnapshotManager";
import { CreateSnapshot } from "./pages/CreateSnapshot";
import { ViewSnapshots } from "./pages/ViewSnapshots";

const controllerConnector = new ControllerConnector({
  preset: "snapshot-manager",
});

function App() {
  const connectors = [
    new InjectedConnector({
      options: { id: "argentX", name: "Ready Wallet (formerly Argent)" },
    }),
    new InjectedConnector({
      options: { id: "braavos", name: "Braavos" },
    }),
    controllerConnector,
  ];

  const provider = jsonRpcProvider({
    rpc: (chain: Chain) => {
      switch (chain) {
        case mainnet:
          return {
            nodeUrl: "https://api.cartridge.gg/x/starknet/mainnet/rpc/v0_8",
          };
        default:
          throw new Error(`Unsupported chain: ${chain.network}`);
      }
    },
  });

  return (
    <StarknetConfig
      chains={[mainnet]}
      provider={provider}
      connectors={connectors}
      explorer={voyager}
    >
      <Router>
        <Routes>
          <Route path="/" element={<Layout />}>
            <Route index element={<SnapshotManager />} />
            <Route path="create" element={<CreateSnapshot />} />
            <Route path="snapshots" element={<ViewSnapshots />} />
            <Route path="snapshots/:id" element={<ViewSnapshots />} />
          </Route>
        </Routes>
      </Router>
    </StarknetConfig>
  );
}

export default App;