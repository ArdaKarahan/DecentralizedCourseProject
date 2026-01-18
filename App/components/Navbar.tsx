"use client";

import { ConnectButton, useCurrentAccount } from "@mysten/dapp-kit";
import Link from "next/link";
import { usePathname } from "next/navigation";
import clsx from "clsx";

export function Navbar() {
  const account = useCurrentAccount();
  const pathname = usePathname();

  const tabs = [
    { name: "About", href: "/" },
    { name: "Create Wallet", href: "/create-wallet" },
    { name: "My Wallets", href: "/my-wallets" },
  ];

  return (
    <div className="flex flex-col w-full">
      {/* Top Bar with Connect Wallet */}
      <div className="flex justify-end p-4 bg-transparent relative z-50">
        <div className="p-[2px] rounded-xl bg-gradient-to-r from-red-500 via-yellow-500 via-green-500 via-blue-500 to-purple-500 animate-gradient-xy">
          <div className="bg-black rounded-[10px]">
            <ConnectButton className="!bg-transparent !text-white !font-bold" />
          </div>
        </div>
      </div>

      {/* Tabs - Only if connected */}
      {account && (
        <div className="flex justify-center gap-8 py-4 border-b border-neon-purple/30 bg-black/20 backdrop-blur-sm">
          {tabs.map((tab) => (
            <Link
              key={tab.name}
              href={tab.href}
              className={clsx(
                "px-6 py-2 rounded-full text-lg font-semibold transition-all duration-300 border-2",
                pathname === tab.href
                  ? "border-neon-pink text-neon-pink shadow-[0_0_10px_var(--neon-pink)]"
                  : "border-transparent text-gray-400 hover:text-white hover:border-neon-purple/50"
              )}
            >
              {tab.name}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
