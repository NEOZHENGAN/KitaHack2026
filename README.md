# 🏃‍♂️ SafeStride - GDG KitaHack 2026 Submission

SafeStride is a proactive, AI-powered tactical companion app designed for runners. It targets **SDG 3 (Good Health)**, **SDG 5 (Gender Equality)**, and **SDG 9 (Innovation & Infrastructure)** by transforming how we approach personal safety in outdoor environments.

## 🌟 Key Features
* **Proactive AI Scanner:** Uses **Google Gemini 2.5 Flash** to analyze the user's GPS context and environmental input (e.g., "dark street"), providing instant safety warnings.
* **Real-time SOS Blackbox:** A 1-tap emergency broadcast system that logs critical survival data to **Firebase Cloud Firestore** and sends SMS alerts with **Google Maps** deep-links.
* **High-Precision Tracker:** Optimized algorithms achieving 1.0-meter GPS sensitivity for live performance tracking.
* **Offline First Aid Manual:** Graceful degradation design ensures vital medical protocols (e.g., Asthma steps, CPR) remain accessible even in data dead-zones.
* **Cloud-Synced Prep:** Secure user authentication and gear checklist synchronization powered by **Firebase Auth**.

## 🛠️ Tech Stack
* **Frontend UI:** Flutter & Dart
* **AI Engine:** Google Generative AI (Gemini 2.5 Flash)
* **Backend & Auth:** Firebase Authentication & Cloud Firestore
* **Location Services:** Geolocator & Google Maps URL Schemes

---

## 🚀 Setup Instructions (How to run this project)

**Important Note for Judges:** For security reasons, the `.env` file containing the Google Gemini API Key has been excluded from this public repository. Please follow the steps below to run the app locally.

### Prerequisites
1.  Flutter SDK installed (Version 3.19.0 or higher).
2.  A valid [Google Gemini API Key](https://aistudio.google.com/app/apikey).
3.  A Firebase project configured for Android/iOS (google-services.json / GoogleService-Info.plist).

### Installation Steps

**1. Clone the repository**

git clone [https://github.com/NEOZHENGAN/KitaHack2026.git](https://github.com/NEOZHENGAN/KitaHack2026.git)
cd safestride

2. Install Flutter dependencies

flutter pub get
3. Set up Environment Variables (Crucial Step)

In the root directory of the project, create a new file named exactly .env.

Add your Gemini API key to this file like so:

Plaintext
GEMINI_API_KEY=your_actual_api_key_here
4. Run the App

flutter run
👥 Team
Team Name: Basic Dragon

Built with ❤️ for GDG KitaHack2026
