"use client";

import { useCurrentAccount, useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { PACKAGE_ID, MODULE_NAME, WALLET_TYPE_PLURALITY, WALLET_TYPE_UNANIMITY } from "../../utils/constants";
import clsx from "clsx";
import { Loader2 } from "lucide-react";

export default function MyWallets() {
  const account = useCurrentAccount();
  const client = useSuiClient();

  const { data: wallets, isLoading, error } = useQuery({
    queryKey: ["my-wallets", account?.address],
    queryFn: async () => {
      if (!account) return [];

      // 1. Fetch WalletCreated events
      // Note: In a production app, you'd paginate this.
      const events = await client.queryEvents({
        query: {
          MoveModule: {
            package: PACKAGE_ID,
            module: MODULE_NAME,
          },
        },
        limit: 50,
        order: "descending",
      });

      // 2. Filter events where user was an initial owner
      const relevantWalletIds = events.data
        .filter((e) => {
          // @ts-ignore
          const owners = e.parsedJson?.owners as string[] || [];
          return owners.some(o => o === account.address);
        })
        // @ts-ignore
        .map((e) => e.parsedJson?.wallet_id as string);

      if (relevantWalletIds.length === 0) return [];

      // 3. Fetch actual objects to confirm current ownership
      const objects = await client.multiGetObjects({
        ids: Array.from(new Set(relevantWalletIds)),
        options: {
          showContent: true,
        },
      });

      // 4. Parse and filter again
      const myWallets = objects
        .map((obj) => {
          const content = obj.data?.content;
          if (content?.dataType !== "moveObject") return null;
          // @ts-ignore
          const fields = content.fields;
          // @ts-ignore
          const owners = fields.owners as string[];
          
          if (!owners.includes(account.address)) return null;

          return {
            id: obj.data?.objectId,
            // @ts-ignore
            walletType: fields.wallet_type as number,
            owners: owners,
          };
        })
        .filter((w) => w !== null);

      return myWallets;
    },
    enabled: !!account,
  });

  if (!account) {
    return (
      <div className="flex justify-center items-center h-[50vh]">
        <p className="text-xl text-gray-400">Please connect your wallet first.</p>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="flex flex-col justify-center items-center h-[50vh] space-y-4">
        <Loader2 className="w-12 h-12 text-neon-pink animate-spin" />
        <p className="text-neon-purple animate-pulse">Fetching your vaults...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex justify-center items-center h-[50vh]">
        <p className="text-red-500">Error loading wallets. Please try again.</p>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-12">
      <h1 className="text-4xl font-bold mb-12 text-center text-transparent bg-clip-text bg-gradient-to-r from-neon-pink to-neon-purple">
        My Wallets
      </h1>

      {wallets && wallets.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {wallets.map((wallet) => (
            <Link
              key={wallet!.id}
              href={`/wallet/${wallet!.id}`}
              className={clsx(
                "block p-6 rounded-2xl border-2 transition-all duration-300 hover:scale-105",
                wallet!.walletType === WALLET_TYPE_PLURALITY
                  ? "border-neon-pink bg-black/40 hover:shadow-[0_0_20px_var(--neon-pink)]"
                  : "border-neon-grey bg-black/40 hover:shadow-[0_0_20px_var(--neon-grey)]"
              )}
            >
              <div className="flex justify-between items-start mb-4">
                <span
                  className={clsx(
                    "px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider",
                    wallet!.walletType === WALLET_TYPE_PLURALITY
                      ? "bg-neon-pink text-black"
                      : "bg-neon-grey text-black"
                  )}
                >
                  {wallet!.walletType === WALLET_TYPE_PLURALITY ? "Plurality" : "Unanimity"}
                </span>
              </div>
              
              <div className="space-y-2">
                <p className="text-gray-400 text-xs uppercase font-semibold">Wallet ID</p>
                <p className="text-white font-mono text-sm truncate" title={wallet!.id}>
                  {wallet!.id}
                </p>
              </div>

              <div className="mt-4 pt-4 border-t border-gray-700">
                <p className="text-gray-400 text-xs">Owners: <span className="text-white">{wallet!.owners.length}</span></p>
              </div>
            </Link>
          ))}
        </div>
      ) : (
        <div className="text-center text-gray-500 mt-12">
          <p className="text-xl">No wallets found.</p>
          <Link href="/create-wallet" className="text-neon-pink hover:underline mt-2 inline-block">
            Create one now &rarr;
          </Link>
        </div>
      )}
    </div>
  );
}