"use client";

import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { PACKAGE_ID, MODULE_NAME, WALLET_TYPE_PLURALITY, WALLET_TYPE_UNANIMITY } from "../../utils/constants";
import clsx from "clsx";
import { useRouter } from "next/navigation";

export default function CreateWallet() {
  const account = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const [walletType, setWalletType] = useState<number | null>(null);
  const [otherOwners, setOtherOwners] = useState("");
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  const handleCreate = () => {
    if (!account || walletType === null) return;
    setLoading(true);

    const owners = [account.address];
    if (otherOwners.trim()) {
      const others = otherOwners.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
      owners.push(...others);
    }

    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::${MODULE_NAME}::create_wallet`,
      arguments: [
        tx.pure.vector("address", owners),
        tx.pure.u8(walletType),
      ],
    });

    signAndExecute(
      { transaction: tx },
      {
        onSuccess: () => {
          alert("Wallet Created Successfully!");
          setLoading(false);
          router.push("/my-wallets");
        },
        onError: (err) => {
          console.error(err);
          alert("Failed to create wallet");
          setLoading(false);
        },
      }
    );
  };

  if (!account) {
    return (
      <div className="flex justify-center items-center h-[50vh]">
        <p className="text-xl text-gray-400">Please connect your wallet first.</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center justify-center py-12 px-4">
      <div className="bg-black/40 border border-neon-purple/30 p-8 rounded-2xl shadow-[0_0_20px_rgba(176,38,255,0.1)] max-w-lg w-full">
        <h1 className="text-3xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-neon-pink to-neon-purple mb-8 text-center">
          Create Multi-Sig Wallet
        </h1>

        <div className="space-y-6">
          <div className="space-y-3">
            <label className="text-gray-300 font-semibold">Select Governance Type</label>
            <div className="flex gap-4">
              <button
                onClick={() => setWalletType(WALLET_TYPE_PLURALITY)}
                className={clsx(
                  "flex-1 p-4 rounded-xl border-2 transition-all duration-300 flex items-center justify-center gap-2",
                  walletType === WALLET_TYPE_PLURALITY
                    ? "border-neon-pink bg-neon-pink/10 text-neon-pink shadow-[0_0_10px_var(--neon-pink)]"
                    : "border-gray-700 text-gray-500 hover:border-gray-500"
                )}
              >
                <div className={clsx("w-4 h-4 rounded-full border-2", walletType === WALLET_TYPE_PLURALITY ? "bg-neon-pink border-neon-pink" : "border-gray-500")} />
                Plurality
              </button>

              <button
                onClick={() => setWalletType(WALLET_TYPE_UNANIMITY)}
                className={clsx(
                  "flex-1 p-4 rounded-xl border-2 transition-all duration-300 flex items-center justify-center gap-2",
                  walletType === WALLET_TYPE_UNANIMITY
                    ? "border-neon-purple bg-neon-purple/10 text-neon-purple shadow-[0_0_10px_var(--neon-purple)]"
                    : "border-gray-700 text-gray-500 hover:border-gray-500"
                )}
              >
                <div className={clsx("w-4 h-4 rounded-full border-2", walletType === WALLET_TYPE_UNANIMITY ? "bg-neon-purple border-neon-purple" : "border-gray-500")} />
                Unanimity
              </button>
            </div>
            <p className="text-xs text-gray-500 text-center mt-2">
              {walletType === WALLET_TYPE_PLURALITY && "Requires > 50% approval for execution."}
              {walletType === WALLET_TYPE_UNANIMITY && "Requires 100% approval for execution."}
            </p>
          </div>

          <div className="space-y-2">
            <label className="text-gray-300 font-semibold">Add Other Owners (Optional)</label>
            <textarea
              value={otherOwners}
              onChange={(e) => setOtherOwners(e.target.value)}
              placeholder="0x..., 0x..."
              className="w-full bg-black/50 border border-gray-700 rounded-lg p-3 text-white focus:outline-none focus:border-neon-blue transition-colors h-24 text-sm"
            />
            <p className="text-xs text-gray-500">Separate addresses with commas. You are automatically added.</p>
          </div>

          <button
            onClick={handleCreate}
            disabled={walletType === null || loading}
            className={clsx(
              "w-full py-4 rounded-xl font-bold text-lg transition-all duration-300",
              walletType !== null && !loading
                ? "bg-gradient-to-r from-neon-pink to-neon-purple text-white hover:opacity-90 shadow-[0_0_20px_rgba(255,0,255,0.4)]"
                : "bg-gray-800 text-gray-500 cursor-not-allowed"
            )}
          >
            {loading ? "Creating..." : "Create Multi-Sig Wallet"}
          </button>
        </div>
      </div>
    </div>
  );
}