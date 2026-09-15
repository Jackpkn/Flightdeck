import React from "react";
import SmoothScroll from "@/components/SmoothScroll";
import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";
import CockpitSimulator from "@/components/CockpitSimulator";
import HomeFeatureCards from "@/components/HomeFeatureCards";
import ComparisonMatrix from "@/components/ComparisonMatrix";
import InstallSection from "@/components/InstallSection";
import Footer from "@/components/Footer";

export default function Home() {
  return (
    <div className="min-h-screen bg-[#040506] text-white selection:bg-[#ff6363] selection:text-white flex flex-col">
      <SmoothScroll />
      <Navbar />
      <main className="flex-1">
        <Hero />
        <CockpitSimulator />
        <HomeFeatureCards />
        <ComparisonMatrix />
        <InstallSection />
      </main>
      <Footer />
    </div>
  );
}
