# agent.md

## Project Overview
This project is a **peer-to-peer (P2P), end-to-end encrypted (E2EE) iOS chat application** built with **SwiftUI**.  
The app prioritizes **maximum privacy**: no message history, no user data saved, no analytics, no push notifications, no third-party tracking.  

Communication is established directly between devices via **WebRTC**. A signaling server may be available, but by default the agent should assume responsibility only for the iOS client.  

## Objectives
- Implement a **minimalistic, secure, text-only messaging app**.  
- Ensure **strong E2EE** and **ephemeral messages** (default lifetime: 24h).  
- Maintain **P2P connectivity** wherever possible, falling back to signaling/relay only when required.  
- Deliver **production-ready SwiftUI code**, not prototypes.  

## Tech Stack
- **Language:** Swift  
- **UI Framework:** SwiftUI  
- **Networking:** [WebRTC iOS/macOS binaries](https://github.com/stasel/WebRTC) via Swift Package Manager or Cocoapods  

## Constraints
- iOS only (default). If explicitly asked and given access, server-related code may be implemented.  
- Text messages only, no media support.  
- No persistent history: messages must be ephemeral.  
- No analytics, push notifications, or third-party SDKs.  
- No user-identifiable data stored or transmitted.  
- Maximum privacy is always the default priority.  

## Rules for the Agent
1. Focus primarily on iOS client development. Only implement server-related work when explicitly requested.  
2. Use SwiftUI for all UI.  
3. Use the provided WebRTC package for connectivity.  
4. Write **production-ready code**, not quick demos.  
5. Do not add terminal build/test instructions — assume Xcode usage.  
6. If a prompt is **unclear**, ask clarifying questions before implementing. Once clarified, then implement.  
7. Default to maximum security: no logging, no debug prints left in production code, no third-party telemetry.  

## Tasks the Agent Should Perform
- Implement SwiftUI views and app structure.  
- Integrate WebRTC for peer connections.  
- Handle ephemeral messaging logic (self-destruct after max 24h).  
- Manage local authentication (biometric + passphrase).  
- Follow best practices for E2EE messaging.  
- Keep code clean, modular, and ready for production.  

## Tasks the Agent Should Avoid
- Do not implement media (images, files, voice) unless explicitly requested.  
- Do not store chat history or user metadata.  
- Do not introduce analytics, ads, push notifications, or tracking.  
- Do not generate server code unless explicitly asked.  
