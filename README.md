# Sentinel

An AI-powered meeting intelligence system designed for enterprise deployment on-premise.

## Overview

Sentinel is an intelligent meeting assistant that automatically records, transcribes, and analyzes meetings. It generates meeting summaries, automatically creates action items, and provides a chat interface for querying historical meeting content using RAG (Retrieval-Augmented Generation).

### Key Features

- **Real-time & Offline Recording**: Record meetings via mobile devices (iOS/Android) or laptops with offline support
- **Speech-to-Text (ASR)**: Automatic transcription of meeting audio
- **AI-Powered Analysis**: Automatic generation of meeting summaries and action items
- **Semantic Search**: Chat-based query interface using RAG with vector embeddings
- **Calendar Integration**: Schedule and manage meeting sessions
- **Admin Dashboard**: System monitoring for resource usage and active sessions
- **On-Premise Deployment**: Full data privacy with on-premise server deployment

## System Architecture

The system consists of:

- **Frontend App**: Desktop / iOS / Android applications for recording and chat
- **Backend API**: NestJS-based API server with WebSocket support
- **ASR Service**: gRPC streaming service for speech-to-text conversion
- **LLM Batch Service**: Batch processing for summaries, action items, and embeddings
- **Chat Module**: RAG and Agent-based chat processing
- **Database**: PostgreSQL with pgvector for semantic search
- **Workflow Engine**: Temporal.io for orchestrating ASR → LLM pipelines

## User Roles

| Role | Description |
|------|-------------|
| **Normal User** | Record meetings, view reports, manage action items, use chat (Basic/Mid plan) |
| **Admin User** | Monitor system resources, view statistics, manage users |
| **Root User** | Full system access for development and debugging |

## Documentation

### Architecture Documents

| Document | Description |
|----------|-------------|
| [System Overview](./systemOverview.md) | System description, user stories, and use cases |
| [Data Flow](./dataflow.md) | Detailed data flow diagrams |
| [System Architecture](./systemArch.md) | Complete system architecture description |
| [Context Diagram](./contextDiagram.md) | C4 Level 1: System context showing users and system boundaries |
| [Container Diagram](./containerDiagram.md) | C4 Level 2: Container architecture showing internal components |

### Diagrams (Mermaid)

- `contextDiagram.mmd` - System context diagram
- `containerDiagram.mmd` - Container architecture diagram
- `systemArch.mmd` - System architecture diagram

## Technology Stack

- **Backend**: NestJS
- **Database**: PostgreSQL with pgvector extension
- **Workflow**: Temporal.io / BullMQ
- **Speech Recognition**: gRPC Streaming
- **LLM**: Support for embedding and chat models
- **Deployment**: Docker on Linux

## Project Status

**Current Stage: Design**

The project is currently in the design phase. No implementation has begun yet.

### Completed Design Artifacts

- [x] System Overview & Requirements
- [x] Data Flow Design
- [x] System Architecture
- [x] Context Diagram (C4 Level 1)
- [x] Container Diagram (C4 Level 2)

### Pending Design Artifacts

- [ ] Component Diagram (C4 Level 3)
- [ ] Database Schema Design
- [ ] Deployment Diagram (C4 Level 4)

## Getting Started

This project is in the design phase. Please refer to the documentation above to understand the system architecture and requirements.

## License

TBD
