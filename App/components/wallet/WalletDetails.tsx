import { ExternalLink, Calendar, Users, FileText, Hash } from "lucide-react";

interface WalletDetailsProps {
  wallet: any;
  creationEvent: any;
  proposalCount: number;
}

export function WalletDetails({ wallet, creationEvent, proposalCount }: WalletDetailsProps) {
  const creationDate = creationEvent 
    ? new Date(Number(creationEvent.timestampMs)).toLocaleDateString(undefined, {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      })
    : "Loading...";

  const creator = creationEvent?.sender || "Unknown";
  const txHash = creationEvent?.id?.txDigest || "Unknown";

  return (
    <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        {/* Info Card */}
        <div className="p-8 rounded-2xl bg-black/40 border border-gray-800 space-y-6">
          <h3 className="text-2xl font-bold text-white flex items-center gap-2">
            <FileText className="text-neon-pink" />
            Wallet Information
          </h3>
          
          <div className="space-y-4">
            <div className="flex justify-between items-center py-2 border-b border-gray-800">
              <span className="text-gray-400 flex items-center gap-2"><Calendar size={16}/> Created On</span>
              <span className="text-white font-mono">{creationDate}</span>
            </div>
            
            <div className="flex justify-between items-center py-2 border-b border-gray-800">
              <span className="text-gray-400 flex items-center gap-2"><Users size={16}/> Creator</span>
              <span className="text-neon-purple font-mono text-sm truncate max-w-[150px]" title={creator}>{creator}</span>
            </div>

            <div className="flex justify-between items-center py-2 border-b border-gray-800">
              <span className="text-gray-400 flex items-center gap-2"><Hash size={16}/> Transaction</span>
              <a 
                href={`https://suiscan.xyz/testnet/tx/${txHash}`} 
                target="_blank" 
                rel="noreferrer"
                className="text-neon-blue hover:underline font-mono text-sm flex items-center gap-1"
              >
                {txHash.slice(0, 8)}...{txHash.slice(-8)}
                <ExternalLink size={12} />
              </a>
            </div>

            <div className="flex justify-between items-center py-2 border-b border-gray-800">
              <span className="text-gray-400">Total Proposals</span>
              <span className="text-white font-bold text-xl">{proposalCount}</span>
            </div>
             <div className="flex justify-between items-center py-2 border-b border-gray-800">
              <span className="text-gray-400">Balance</span>
              <span className="text-white font-bold text-xl">{(Number(wallet?.content?.fields?.balance || 0) / 1_000_000_000).toFixed(4)} SUI</span>
            </div>
          </div>
        </div>

        {/* Owners Card */}
        <div className="p-8 rounded-2xl bg-black/40 border border-gray-800">
          <h3 className="text-2xl font-bold text-white flex items-center gap-2 mb-6">
            <Users className="text-neon-purple" />
            Owners ({wallet?.content?.fields?.owners?.length || 0})
          </h3>
          
          <div className="space-y-2 max-h-[300px] overflow-y-auto custom-scrollbar pr-2">
            {wallet?.content?.fields?.owners?.map((owner: string, idx: number) => (
              <div key={owner} className="p-3 bg-white/5 rounded-lg flex items-center gap-3 font-mono text-sm text-gray-300 border border-transparent hover:border-neon-purple/50 transition-colors">
                <div className="w-6 h-6 rounded-full bg-gradient-to-br from-neon-pink to-neon-purple flex items-center justify-center text-[10px] font-bold text-black">
                  {idx + 1}
                </div>
                <span className="truncate">{owner}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}