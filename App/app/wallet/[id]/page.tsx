"use client";

import { use, useState } from "react";
import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_ID, MODULE_NAME } from "../../../utils/constants";
import { WalletDetails } from "../../../components/wallet/WalletDetails";
import { WalletProposals } from "../../../components/wallet/WalletProposals";
import { WalletStats } from "../../../components/wallet/WalletStats";
import { CreateProposalModal } from "../../../components/wallet/CreateProposalModal";
import clsx from "clsx";
import { Loader2 } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";

export default function WalletPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const client = useSuiClient();
  const [activeTab, setActiveTab] = useState<"details" | "proposals" | "stats">("details");
  const [isModalOpen, setIsModalOpen] = useState(false);

  // 1. Fetch Wallet Object
  const { data: wallet, isLoading: walletLoading } = useQuery({
    queryKey: ["wallet", id],
    queryFn: async () => {
      const res = await client.getObject({
        id,
        options: { showContent: true },
      });
      return res.data;
    },
  });

  // 2. Fetch WalletCreated Event (for metadata)
  const { data: creationEvent, isLoading: eventLoading } = useQuery({
    queryKey: ["wallet-creation-event", id],
    queryFn: async () => {
      // In a real app, you'd want an indexer. Here we scan recent events.
      let cursor = null;
      let hasNextPage = true;
      
      while (hasNextPage) {
        const events = await client.queryEvents({
          query: { MoveEventType: `${PACKAGE_ID}::${MODULE_NAME}::WalletCreated` },
          order: "descending",
          limit: 50,
          cursor,
        });

        const found = events.data.find((e) => (e.parsedJson as any)?.wallet_id === id);
        if (found) return found;

        cursor = events.nextCursor;
        hasNextPage = events.hasNextPage;
        if (!cursor) break; 
      }
      return null;
    },
  });

  // 3. Fetch Proposals
  const { data: proposals, isLoading: proposalsLoading, refetch: refetchProposals } = useQuery({
    queryKey: ["wallet-proposals", id],
    queryFn: async () => {
      // 3a. Find ProposalCreated events for this wallet
      let allProposalIds: string[] = [];
      let cursor = null;
      let hasNextPage = true;

      // Scan recent 100 events for demo
      const events = await client.queryEvents({
                  query: { MoveEventType: `${PACKAGE_ID}::${MODULE_NAME}::ProposalCreated` },        order: "descending",
        limit: 50,
      });

      const relevantEvents = events.data.filter((e) => (e.parsedJson as any)?.wallet_id === id);
      allProposalIds = relevantEvents.map((e) => (e.parsedJson as any)?.proposal_id);

      if (allProposalIds.length === 0) return [];

      // 3b. Fetch Proposal Objects
      const objects = await client.multiGetObjects({
        ids: allProposalIds,
        options: { showContent: true },
      });

      return objects.map((obj) => ({
        id: obj.data?.objectId!,
        data: obj.data!,
      }));
    },
  });

  const isLoading = walletLoading || eventLoading || proposalsLoading;

  if (isLoading) {
    return (
      <div className="flex flex-col justify-center items-center h-[60vh] space-y-4">
        <Loader2 className="w-16 h-16 text-neon-pink animate-spin" />
        <p className="text-neon-purple animate-pulse text-xl">Loading Wallet Data...</p>
      </div>
    );
  }

  if (!wallet) {
    return (
      <div className="flex justify-center items-center h-[50vh] flex-col gap-4">
        <p className="text-red-500 text-xl">Wallet Not Found</p>
        <Link href="/my-wallets" className="text-blue-400 hover:underline">Back to My Wallets</Link>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8">
      {/* Header */}
      <div className="mb-8 flex flex-col md:flex-row justify-between items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white mb-2">Multi-Sig Wallet</h1>
          <p className="text-gray-400 font-mono text-sm">{id}</p>
        </div>
        <div className="flex gap-2">
           <button 
             onClick={() => setIsModalOpen(true)}
             className="px-6 py-2 bg-gradient-to-r from-neon-pink to-neon-purple rounded-full text-white font-bold hover:opacity-90 transition-opacity shadow-[0_0_15px_rgba(255,0,255,0.4)]"
           >
             + New Proposal
           </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-gray-800 mb-8">
        {(["details", "proposals", "stats"] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={clsx(
              "px-8 py-3 font-semibold text-lg transition-all duration-300 border-b-2 capitalize",
              activeTab === tab
                ? "border-neon-pink text-neon-pink"
                : "border-transparent text-gray-500 hover:text-white hover:border-gray-600"
            )}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="min-h-[400px]">
        {activeTab === "details" && (
          <WalletDetails 
            wallet={wallet} 
            creationEvent={creationEvent} 
            proposalCount={proposals?.length || 0} 
          />
        )}
        {activeTab === "proposals" && (
          <WalletProposals 
            proposals={proposals || []} 
            walletId={id} 
            refetch={refetchProposals} 
          />
        )}
        {activeTab === "stats" && (
          <WalletStats proposals={proposals || []} />
        )}
      </div>

      <CreateProposalModal 
        isOpen={isModalOpen} 
        onClose={() => setIsModalOpen(false)} 
        walletId={id} 
        refetch={refetchProposals} 
      />
    </div>
  );
}