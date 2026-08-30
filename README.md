# 🌿 AuraSync AI: Community-Driven Waste Intelligence

AuraSync AI is a professional-grade mobile application designed to bridge the gap between individual waste disposal and municipal logistics. By leveraging Google Gemini AI for dynamic, server-routed classification and Supabase Realtime for geospatial syncing, AuraSync transforms passive waste management into an active, gamified community ecosystem.

This project directly addresses UN Sustainable Development Goals 12 (Responsible Consumption and Production) and 11 (Sustainable Cities and Communities).

## 🌎 Vision & Social Impact
In many urban environments, "leakage" occurs when specialized waste (E-waste, medical, toxic) is disposed of in general bins due to a lack of immediate information or collection logistics.

AuraSync AI solves this through:
* **Behavioral Change:** Providing instant "Eco-Insights" at the moment of disposal to educate users on their environmental footprint.
* **Logistical Optimization:** Using "Swarm Mapping" to allow citizens to identify waste hotspots for centralized collectors.
* **Gamified Sustainability:** Incentivizing the diversion of toxic materials from landfills through a points-based ledger and local sector leaderboards.

---

## 🚀 Core Functionalities

### Dual-Role Architecture
AuraSync features a dynamic routing gate that provides entirely different experiences based on user privileges:
* **Citizen Users:** Scan waste, track personal impact, view leaderboards, and await local collection dispatches.
* **Collector Admins:** View the macroscopic S2-Grid map, monitor waste density in real-time, change error-handling boundaries, and dispatch collection vehicles to high-yield sectors.

### Dynamic AI-Powered Waste Analysis
Utilizing server-side routing via Supabase, the app completely bypasses static API limitations by dynamically executing queries across available models (`gemini-2.5-flash`, `gemini-2.5-pro`, `gemini-2.5-flash-lite`, etc.) based on active database rules.
* **Classification:** Automatically categorizes waste across dozens of parameters (E-waste, Chemical, Medical, etc.) via a live camera feed.
* **Toxicity Guard:** Flags hazardous materials (like lithium-ion batteries or blister packs) with high-priority alerts.
* **Educational Overlay:** Displays safe disposal tips and eco-facts tailored to the specific item scanned.

### The "Swarm" Map (Geospatial Sync)
Every verified scan is converted to a generalized Level 14 S2 Geometry Token to protect exact user locations while providing actionable data.
* **Real-time Visualization:** Admins can view a heatmap of uncollected waste density across city sectors.
* **Active Ledgers:** Users can manage their pending scans before the collector arrives.

### Live Operations & Dispatch (Supabase Realtime)
When a Collector Admin authorizes entry and dispatches a vehicle to a specific S2 Grid sector, AuraSync utilizes PostgreSQL triggers to instantly alert the community.
* **In-App Banners:** Citizens in the targeted sector receive an immediate, animated floating notification warning them to prepare their waste.
* **Local Notifications:** Fallback scheduled alarms (48h, 24h, 15m) trigger as the collection window approaches.

---

## 🛠️ Technical Architecture

* **Frontend:** Flutter (v3.19.0+)
* **AI Engine:** Google Generative AI Dart SDK (Dynamic Routing Setup)
* **Backend & Auth:** Supabase (PostgreSQL, Auth, Storage, Realtime Subscriptions)
* **Maps & Geo:** Google Maps SDK, Google S2 Geometry Engine Logic
* **Environment Security:** `flutter_dotenv`

---

## 🏃 Setup & Execution Guide

To maintain professional security standards, no API keys or database credentials are hardcoded in this repository.

### Prerequisites
* Ensure the Flutter SDK is installed and added to your `PATH`.
* Obtain a Gemini API Key from Google AI Studio.
* Initialize a Supabase Project and obtain your Project URL and Anon Key.

### Clone the Repository
```bash

git clone [https://github.com/YOUR_USERNAME/aurasync_ai.git](https://github.com/YOUR_USERNAME/aurasync_ai.git)
cd aurasync_ai
flutter pub get
Environment Setup (Crucial)
Create a file named exactly .env in the root directory of the project (at the same level as pubspec.yaml). Add your credentials:

Code snippet
SUPABASE_URL=your_actual_supabase_project_url
SUPABASE_ANON_KEY=your_actual_supabase_anon_key
GEMINI_API_KEY=your_actual_gemini_api_key
(Note: The .env file is intentionally ignored by git to protect your production keys).

Database Schema Requirements
Your Supabase project must contain the following core tables for the application layer to resolve correctly. Run this initialization script inside your Supabase SQL Editor:

SQL
-- 1. Profiles Table
CREATE TABLE public.profiles (
  id uuid REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  display_name text,
  avatar_url text,
  role text DEFAULT 'user'::text,
  trust_score integer DEFAULT 100,
  phone text,
  address text
);

-- 2. Waste Items Ledger
CREATE TABLE public.waste_items (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id uuid REFERENCES public.profiles(id),
  material_type text,
  category text,
  eco_points integer,
  weight_grams integer,
  status text DEFAULT 'pending'::text,
  s2_cell_id text
);

-- 3. Swarm Broadcasts Realtime Feed
CREATE TABLE public.swarm_broadcasts (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  s2_cell_id text,
  message text,
  scheduled_time timestamp with time zone,
  status text,
  ttl_expiry timestamp with time zone
);

-- 4. Remote App Settings (Dynamic Gemini Configurations)
CREATE TABLE public.app_settings (
  id integer PRIMARY KEY,
  active_gemini_model text NOT NULL DEFAULT 'gemini-1.5-flash'
);

-- Insert Default Runtime Configuration
INSERT INTO public.app_settings (id, active_gemini_model)
VALUES (1, 'gemini-1.5-flash')
ON CONFLICT (id) DO NOTHING;

-- Enable row level read privileges for settings
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read access" ON public.app_settings FOR SELECT USING (true);
⚠️ Realtime Replication Note: Ensure that Realtime (Replication) is toggled ON for the swarm_broadcasts table in your Supabase Dashboard under Database -> Replication to enable the PostgreSQL trigger banner streams.

Run the Project

Bash
flutter run

