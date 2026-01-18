"use client";

import { useState } from "react";
import { 
  STATUS_PENDING, STATUS_EXECUTED, STATUS_REJECTED, STATUS_EXPIRED,
  ACTION_SEND_SUI, ACTION_ADD_OWNER, ACTION_REMOVE_OWNER,
  STATUS_LABELS, ACTION_LABELS, PACKAGE_ID, MODULE_NAME
} from "../../utils/constants";
import clsx from "clsx";
import { ChevronDown, ChevronUp, Check, X, Clock, Send, UserPlus, UserMinus, Play } from "lucide-react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";

interface Proposal {
  id: string;
  data: any;
}

interface WalletProposalsProps {
  proposals: Proposal[];
  walletId: string;
  refetch: () => void;
}

export function WalletProposals({ proposals, walletId, refetch }: WalletProposalsProps) {
  const [filterAction, setFilterAction] = useState<number | null>(null);
  const [filterStatus, setFilterStatus] = useState<number | null>(null);

  const filteredProposals = proposals.filter((p) => {
    const fields = p.data.content.fields;
    let status = fields.status;

    // Calculate effective status (Client-side Expiry)
    const expiryMsVal = fields.expiry_ms?.fields?.contents || fields.expiry_ms;
    const expiryMs = expiryMsVal ? Number(expiryMsVal) : null;
    const isExpired = status === STATUS_PENDING && expiryMs && Date.now() > expiryMs;

    if (isExpired) {
      status = STATUS_EXPIRED;
    }

    const actionMatch = filterAction === null || fields.action_type === filterAction;
    const statusMatch = filterStatus === null || status === filterStatus;
    return actionMatch && statusMatch;
  });

  return (
    <div className="space-y-6">
      {/* Filters */}
      <div className="flex flex-col md:flex-row gap-4 p-4 bg-black/40 rounded-xl border border-gray-800">
        <div className="flex-1 space-y-2">
          <label className="text-xs text-gray-400 uppercase font-bold">Filter by Action</label>
          <div className="flex flex-wrap gap-2">
            <button 
              onClick={() => setFilterAction(null)} 
              className={clsx("px-3 py-1 rounded-full text-sm border", filterAction === null ? "bg-white text-black border-white" : "border-gray-600 text-gray-400 hover:border-white")}
            >
              All
            </button>
            {[ACTION_SEND_SUI, ACTION_ADD_OWNER, ACTION_REMOVE_OWNER].map((action) => (
              <button
                key={action}
                onClick={() => setFilterAction(action === filterAction ? null : action)}
                className={clsx("px-3 py-1 rounded-full text-sm border", filterAction === action ? "bg-neon-blue/20 text-neon-blue border-neon-blue" : "border-gray-600 text-gray-400 hover:border-neon-blue")}
              >
                {ACTION_LABELS[action as keyof typeof ACTION_LABELS]}
              </button>
            ))}
          </div>
        </div>

        <div className="flex-1 space-y-2">
          <label className="text-xs text-gray-400 uppercase font-bold">Filter by Status</label>
          <div className="flex flex-wrap gap-2">
            <button 
              onClick={() => setFilterStatus(null)} 
              className={clsx("px-3 py-1 rounded-full text-sm border", filterStatus === null ? "bg-white text-black border-white" : "border-gray-600 text-gray-400 hover:border-white")}
            >
              All
            </button>
            {[STATUS_PENDING, STATUS_EXECUTED, STATUS_REJECTED, STATUS_EXPIRED].map((status) => (
              <button
                key={status}
                onClick={() => setFilterStatus(status === filterStatus ? null : status)}
                className={clsx(
                  "px-3 py-1 rounded-full text-sm border",
                  filterStatus === status 
                    ? status === STATUS_EXECUTED ? "bg-neon-green/20 text-neon-green border-neon-green"
                    : status === STATUS_REJECTED ? "bg-neon-red/20 text-neon-red border-neon-red"
                    : status === STATUS_PENDING ? "bg-neon-blue/20 text-neon-blue border-neon-blue"
                    : "bg-neon-orange/20 text-neon-orange border-neon-orange"
                    : "border-gray-600 text-gray-400 hover:border-white"
                )}
              >
                {STATUS_LABELS[status as keyof typeof STATUS_LABELS]}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* List */}
      <div className="space-y-4">
        {filteredProposals.length > 0 ? (
          filteredProposals.map((p) => (
            <ProposalItem key={p.id} proposal={p} walletId={walletId} refetch={refetch} />
          ))
        ) : (
          <p className="text-center text-gray-500 py-8">No proposals found matching criteria.</p>
        )}
      </div>
    </div>
  );
}

function ProposalItem({ proposal, walletId, refetch }: { proposal: Proposal, walletId: string, refetch: () => void }) {
  const [expanded, setExpanded] = useState(false);
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const account = useCurrentAccount();

  const fields = proposal.data.content.fields;
  let status = fields.status;
  
  // Calculate client-side expiry
  const expiryMsVal = fields.expiry_ms?.fields?.contents || fields.expiry_ms;
  const expiryMs = expiryMsVal ? Number(expiryMsVal) : null;
  const isExpired = status === STATUS_PENDING && expiryMs && Date.now() > expiryMs;

  if (isExpired) {
    status = STATUS_EXPIRED;
  }

  const actionType = fields.action_type;
  const statusLabel = STATUS_LABELS[status as keyof typeof STATUS_LABELS];
  const actionLabel = ACTION_LABELS[actionType as keyof typeof ACTION_LABELS];
  const proposalId = proposal.id;
  
  // Stats
  const approvalCount = Number(fields.approval_count);
  const rejectionCount = Number(fields.rejection_count);
  const voters = fields.voters?.fields?.contents || []; // VecSet
  const snapshotOwners = fields.snapshot_owners || [];
  const expiryDateStr = expiryMs ? new Date(expiryMs).toLocaleString() : "No Expiry";

  // Colors based on status
  const statusColor = 
    status === STATUS_EXECUTED ? "text-neon-green border-neon-green shadow-[0_0_10px_var(--neon-green)]" :
    status === STATUS_REJECTED ? "text-neon-red border-neon-red shadow-[0_0_10px_var(--neon-red)]" :
    status === STATUS_PENDING ? "text-neon-blue border-neon-blue shadow-[0_0_10px_var(--neon-blue)]" :
    "text-neon-orange border-neon-orange shadow-[0_0_10px_var(--neon-orange)]";

  const borderColor = 
    status === STATUS_EXECUTED ? "border-neon-green/50 hover:border-neon-green" :
    status === STATUS_REJECTED ? "border-neon-red/50 hover:border-neon-red" :
    status === STATUS_PENDING ? "border-neon-blue/50 hover:border-neon-blue" :
    "border-neon-orange/50 hover:border-neon-orange";

  const handleVote = (approve: boolean) => {
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::${MODULE_NAME}::vote`,
      arguments: [
        tx.object(walletId),
        tx.object(proposalId),
        tx.pure.bool(approve),
        tx.object("0x6"), // Clock
      ],
    });
    signAndExecute({ transaction: tx }, { onSuccess: () => { alert("Vote Cast!"); refetch(); }, onError: (e) => console.error(e) });
  };

  const handleExecute = () => {
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::${MODULE_NAME}::execute_proposal`,
      arguments: [
        tx.object(walletId),
        tx.object(proposalId),
        tx.object("0x6"), // Clock
      ],
    });
    signAndExecute(
      { transaction: tx }, 
      { 
        onSuccess: () => { alert("Executed!"); refetch(); }, 
        onError: (e) => {
          console.error(e);
          // @ts-ignore
          alert(`Execution Failed: ${e.message || "Unknown error"}`);
        } 
      }
    );
  };

  const canVote = !isExpired && status === STATUS_PENDING && account && snapshotOwners.includes(account.address) && !voters.includes(account.address);
  // Simple check for execution availability (could be more robust with threshold check, but contract handles it)
  const canExecute = !isExpired && status === STATUS_PENDING; 

  return (
    <div 
      className={clsx("rounded-xl border bg-black/60 transition-all duration-300 overflow-hidden", borderColor)}
    >
      <div 
        onClick={() => setExpanded(!expanded)}
        className="p-6 cursor-pointer flex justify-between items-center"
      >
        <div className="space-y-2">
          <span className={clsx("px-3 py-1 rounded-full text-xs font-bold uppercase border", statusColor)}>
            {statusLabel}
          </span>
          <div className="flex items-center gap-2 text-gray-400 font-semibold">
            {actionType === ACTION_SEND_SUI && <Send size={16}/>}
            {actionType === ACTION_ADD_OWNER && <UserPlus size={16}/>}
            {actionType === ACTION_REMOVE_OWNER && <UserMinus size={16}/>}
            {actionLabel}
          </div>
          <p className="text-gray-600 font-mono text-xs">{proposalId}</p>
        </div>
        
        {expanded ? <ChevronUp className="text-gray-400"/> : <ChevronDown className="text-gray-400"/>}
      </div>

      {expanded && (
        <div className="px-6 pb-6 pt-2 border-t border-gray-800 bg-black/20 animate-in slide-in-from-top-2">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            <div className="space-y-2">
              <p className="text-xs text-gray-400 uppercase">Target / Value</p>
              <p className="text-white font-mono text-sm break-all">{fields.target_address}</p>
              {actionType === ACTION_SEND_SUI && (
                <p className="text-neon-green font-bold">{(Number(fields.amount) / 1_000_000_000).toFixed(4)} SUI</p>
              )}
            </div>
            
            <div className="space-y-2">
              <p className="text-xs text-gray-400 uppercase">Voting Stats</p>
              <div className="flex gap-4">
                <div className="text-neon-green">
                  <span className="text-xl font-bold">{approvalCount}</span> Approved
                </div>
                <div className="text-neon-red">
                  <span className="text-xl font-bold">{rejectionCount}</span> Rejected
                </div>
              </div>
              <p className={clsx("text-xs", isExpired ? "text-neon-orange font-bold" : "text-gray-500")}>
                Expiry: {expiryDateStr}
              </p>
            </div>
          </div>

          <div className="mb-6">
             <p className="text-xs text-gray-400 uppercase mb-2">Snapshot Owners (Voters)</p>
             <div className="flex flex-wrap gap-2">
               {snapshotOwners.map((o: string) => (
                 <span key={o} className={clsx("px-2 py-1 rounded text-xs font-mono", voters.includes(o) ? "bg-gray-700 text-gray-300" : "bg-gray-800 text-gray-500")}>
                   {o.slice(0,6)}...{o.slice(-4)} {voters.includes(o) && "✓"}
                 </span>
               ))}
             </div>
          </div>

          {/* Actions */}
          <div className="flex gap-4 pt-4 border-t border-gray-800">
            {canVote && (
              <>
                <button 
                  onClick={(e) => { e.stopPropagation(); handleVote(true); }}
                  className="flex-1 bg-neon-green/20 text-neon-green border border-neon-green py-2 rounded-lg hover:bg-neon-green/40 font-bold flex justify-center items-center gap-2"
                >
                  <Check size={16} /> Approve
                </button>
                <button 
                  onClick={(e) => { e.stopPropagation(); handleVote(false); }}
                  className="flex-1 bg-neon-red/20 text-neon-red border border-neon-red py-2 rounded-lg hover:bg-neon-red/40 font-bold flex justify-center items-center gap-2"
                >
                  <X size={16} /> Reject
                </button>
              </>
            )}
            
            {canExecute && (
              <button 
                onClick={(e) => { e.stopPropagation(); handleExecute(); }}
                className="flex-1 bg-neon-blue/20 text-neon-blue border border-neon-blue py-2 rounded-lg hover:bg-neon-blue/40 font-bold flex justify-center items-center gap-2"
              >
                <Play size={16} /> Execute
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}