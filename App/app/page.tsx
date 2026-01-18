export default function About() {
  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] text-center space-y-8">
      <h1 className="text-6xl md:text-8xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-neon-pink to-neon-purple drop-shadow-[0_0_15px_rgba(255,0,255,0.5)] animate-pulse">
        NEON MULTISIG
      </h1>
      
      <p className="text-xl md:text-2xl text-gray-300 max-w-2xl leading-relaxed border-l-4 border-neon-purple pl-6 py-2 bg-white/5 rounded-r-xl">
        The future of decentralized governance. <br/>
        Secure your assets with <span className="text-neon-pink font-bold">Plurality</span> or <span className="text-neon-purple font-bold">Unanimity</span> consensus.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8 mt-12 w-full max-w-4xl">
        <div className="p-8 rounded-2xl bg-black/40 border border-neon-pink/30 hover:border-neon-pink shadow-[0_0_20px_rgba(255,0,255,0.1)] hover:shadow-[0_0_30px_rgba(255,0,255,0.3)] transition-all duration-500 group">
          <h2 className="text-3xl font-bold text-neon-pink mb-4 group-hover:scale-105 transition-transform">Plurality</h2>
          <p className="text-gray-400">
            Majority rules. Decisions are executed when more than 50% of owners approve. Perfect for flexible team management.
          </p>
        </div>

        <div className="p-8 rounded-2xl bg-black/40 border border-neon-purple/30 hover:border-neon-purple shadow-[0_0_20px_rgba(176,38,255,0.1)] hover:shadow-[0_0_30px_rgba(176,38,255,0.3)] transition-all duration-500 group">
          <h2 className="text-3xl font-bold text-neon-purple mb-4 group-hover:scale-105 transition-transform">Unanimity</h2>
          <p className="text-gray-400">
            Absolute consensus. Requires 100% owner approval for any action. The ultimate security for high-value vaults.
          </p>
        </div>
      </div>
    </div>
  );
}