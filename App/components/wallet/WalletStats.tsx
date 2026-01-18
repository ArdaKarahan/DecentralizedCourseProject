"use client";

import { useCurrentAccount } from "@mysten/dapp-kit";
import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from "recharts";
import { STATUS_PENDING, STATUS_EXECUTED, STATUS_REJECTED, STATUS_EXPIRED, STATUS_LABELS } from "../../utils/constants";

interface WalletStatsProps {
  proposals: any[];
}

export function WalletStats({ proposals }: WalletStatsProps) {
  const account = useCurrentAccount();

  // 1. Wallet Activity Data
  const total = proposals.length;
  const statusCounts = proposals.reduce((acc, p) => {
    const fields = p.data.content.fields;
    let status = fields.status;

    // Calculate effective status (Client-side Expiry)
    const expiryMsVal = fields.expiry_ms?.fields?.contents || fields.expiry_ms;
    const expiryMs = expiryMsVal ? Number(expiryMsVal) : null;
    const isExpired = status === STATUS_PENDING && expiryMs && Date.now() > expiryMs;

    if (isExpired) {
      status = STATUS_EXPIRED;
    }

    acc[status] = (acc[status] || 0) + 1;
    return acc;
  }, {} as Record<number, number>);

  const walletActivityData = [
    { name: STATUS_LABELS[STATUS_EXECUTED], value: statusCounts[STATUS_EXECUTED] || 0, color: "var(--neon-green)" },
    { name: STATUS_LABELS[STATUS_REJECTED], value: statusCounts[STATUS_REJECTED] || 0, color: "var(--neon-red)" },
    { name: STATUS_LABELS[STATUS_PENDING], value: statusCounts[STATUS_PENDING] || 0, color: "var(--neon-blue)" },
    { name: STATUS_LABELS[STATUS_EXPIRED], value: statusCounts[STATUS_EXPIRED] || 0, color: "var(--neon-orange)" },
  ].filter(d => d.value > 0);

  // 2. User Activity Data
  const userCounts = proposals.reduce((acc, p) => {
    const creator = p.data.content.fields.creator;
    if (account && creator === account.address) {
      acc.me = (acc.me || 0) + 1;
    } else {
      acc.others = (acc.others || 0) + 1;
    }
    return acc;
  }, { me: 0, others: 0 });

  const userActivityData = [
    { name: "My Proposals", value: userCounts.me, color: "var(--neon-pink)" },
    { name: "Others", value: userCounts.others, color: "var(--neon-purple)" },
  ].filter(d => d.value > 0);

  if (total === 0) {
    return (
      <div className="flex justify-center items-center h-[300px] text-gray-500">
        No proposals yet to generate statistics.
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-8 animate-in fade-in duration-500">
      {/* Wallet Activity Chart */}
      <div className="bg-black/40 border border-gray-800 rounded-2xl p-6 flex flex-col items-center">
        <h3 className="text-xl font-bold text-white mb-4">Proposal Status Distribution</h3>
        <div className="w-full h-[300px]">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={walletActivityData}
                cx="50%"
                cy="50%"
                innerRadius={60}
                outerRadius={80}
                paddingAngle={5}
                dataKey="value"
              >
                {walletActivityData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} stroke="none" />
                ))}
              </Pie>
              <Tooltip 
                contentStyle={{ backgroundColor: '#000', borderColor: '#333', borderRadius: '8px' }}
                itemStyle={{ color: '#fff' }}
              />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* User Activity Chart */}
      <div className="bg-black/40 border border-gray-800 rounded-2xl p-6 flex flex-col items-center">
        <h3 className="text-xl font-bold text-white mb-4">User Activity</h3>
        <div className="w-full h-[300px]">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={userActivityData}
                cx="50%"
                cy="50%"
                innerRadius={60}
                outerRadius={80}
                paddingAngle={5}
                dataKey="value"
              >
                {userActivityData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} stroke="none" />
                ))}
              </Pie>
              <Tooltip 
                contentStyle={{ backgroundColor: '#000', borderColor: '#333', borderRadius: '8px' }}
                itemStyle={{ color: '#fff' }}
              />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
}