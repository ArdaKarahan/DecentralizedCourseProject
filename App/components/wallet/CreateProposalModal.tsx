"use client";

import { useState } from "react";
import { X, Clock } from "lucide-react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { 
  PACKAGE_ID, MODULE_NAME, 
  ACTION_SEND_SUI, ACTION_ADD_OWNER, ACTION_REMOVE_OWNER 
} from "../../utils/constants";
import clsx from "clsx";

interface CreateProposalModalProps {
  isOpen: boolean;
  onClose: () => void;
  walletId: string;
  refetch: () => void;
}

export function CreateProposalModal({ isOpen, onClose, walletId, refetch }: CreateProposalModalProps) {
  const account = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  
  const [actionType, setActionType] = useState(ACTION_SEND_SUI);
  const [target, setTarget] = useState("");
  const [amount, setAmount] = useState("");
  
  // Duration State
  const [days, setDays] = useState("0");
  const [hours, setHours] = useState("0");
  const [minutes, setMinutes] = useState("0");
  const [seconds, setSeconds] = useState("0");
  
  const [loading, setLoading] = useState(false);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    const tx = new Transaction();
    
    // Convert Amount to MIST if sending SUI
    const amountMist = actionType === ACTION_SEND_SUI 
      ? BigInt(Math.floor(parseFloat(amount) * 1_000_000_000)) 
      : BigInt(0);

    // Calculate Expiry Ms from duration
    const totalSeconds = 
      (parseInt(days) || 0) * 86400 + 
      (parseInt(hours) || 0) * 3600 + 
      (parseInt(minutes) || 0) * 60 + 
      (parseInt(seconds) || 0);
    
    const expiryMs = totalSeconds > 0 ? Date.now() + (totalSeconds * 1000) : null;

    tx.moveCall({
      target: `${PACKAGE_ID}::${MODULE_NAME}::create_proposal`,
      arguments: [
        tx.object(walletId),
        tx.pure.u8(actionType),
        tx.pure.address(target),
        tx.pure.u64(amountMist),
        tx.pure.option("u64", expiryMs),
      ],
    });

    signAndExecute(
      { transaction: tx },
      {
        onSuccess: () => {
          alert("Proposal Created!");
          setLoading(false);
          setAmount("");
          setTarget("");
          setDays("0");
          setHours("0");
          setMinutes("0");
          setSeconds("0");
          refetch();
          onClose();
        },
        onError: (err) => {
          console.error(err);
          alert("Failed to create proposal");
          setLoading(false);
        },
      }
    );
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
      <div className="bg-[#1a1a2e] border border-neon-purple rounded-2xl w-full max-w-md p-6 relative shadow-[0_0_30px_rgba(176,38,255,0.2)]">
        <button onClick={onClose} className="absolute top-4 right-4 text-gray-400 hover:text-white">
          <X size={24} />
        </button>
        
        <h2 className="text-2xl font-bold text-white mb-6">New Proposal</h2>
        
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <label className="text-sm text-gray-400">Action Type</label>
            <div className="flex gap-2">
              {[
                { val: ACTION_SEND_SUI, label: "Send SUI" },
                { val: ACTION_ADD_OWNER, label: "Add Owner" },
                { val: ACTION_REMOVE_OWNER, label: "Remove Owner" }
              ].map((opt) => (
                <button
                  key={opt.val}
                  type="button"
                  onClick={() => setActionType(opt.val)}
                  className={clsx(
                    "flex-1 py-2 rounded-lg text-xs font-bold transition-colors border",
                    actionType === opt.val
                      ? "bg-neon-pink/20 text-neon-pink border-neon-pink"
                      : "bg-transparent text-gray-400 border-gray-700 hover:border-gray-500"
                  )}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-2">
            <label className="text-sm text-gray-400">
              {actionType === ACTION_SEND_SUI ? "Recipient Address" : "Owner Address"}
            </label>
            <input 
              type="text" 
              required
              value={target}
              onChange={(e) => setTarget(e.target.value)}
              className="w-full bg-black/50 border border-gray-700 rounded-lg p-3 text-white focus:outline-none focus:border-neon-purple"
              placeholder="0x..."
            />
          </div>

          {actionType === ACTION_SEND_SUI && (
            <div className="space-y-2">
              <label className="text-sm text-gray-400">Amount (SUI)</label>
              <input 
                type="number" 
                step="any"
                min="0"
                required
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="w-full bg-black/50 border border-gray-700 rounded-lg p-3 text-white focus:outline-none focus:border-neon-purple"
                placeholder="1.0"
              />
            </div>
          )}

          <div className="space-y-2">
             <label className="text-sm text-gray-400 flex items-center gap-2">
               <Clock size={14} /> Expiry Duration (Relative)
             </label>
             <div className="grid grid-cols-4 gap-2">
                <div className="space-y-1">
                  <p className="text-[10px] text-gray-500 uppercase text-center">Days</p>
                  <input type="number" min="0" value={days} onChange={e => setDays(e.target.value)} className="w-full bg-black/50 border border-gray-700 rounded-lg p-2 text-white text-center text-sm" />
                </div>
                <div className="space-y-1">
                  <p className="text-[10px] text-gray-500 uppercase text-center">Hrs</p>
                  <input type="number" min="0" value={hours} onChange={e => setHours(e.target.value)} className="w-full bg-black/50 border border-gray-700 rounded-lg p-2 text-white text-center text-sm" />
                </div>
                <div className="space-y-1">
                  <p className="text-[10px] text-gray-500 uppercase text-center">Min</p>
                  <input type="number" min="0" value={minutes} onChange={e => setMinutes(e.target.value)} className="w-full bg-black/50 border border-gray-700 rounded-lg p-2 text-white text-center text-sm" />
                </div>
                <div className="space-y-1">
                  <p className="text-[10px] text-gray-500 uppercase text-center">Sec</p>
                  <input type="number" min="0" value={seconds} onChange={e => setSeconds(e.target.value)} className="w-full bg-black/50 border border-gray-700 rounded-lg p-2 text-white text-center text-sm" />
                </div>
             </div>
             <p className="text-[10px] text-gray-500 italic">Leaves blank or set all to 0 for no expiry.</p>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3 mt-4 bg-gradient-to-r from-neon-pink to-neon-purple rounded-xl text-white font-bold hover:opacity-90 transition-opacity"
          >
            {loading ? "Creating..." : "Create Proposal"}
          </button>
        </form>
      </div>
    </div>
  );
}