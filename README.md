# hilljb-gcp-dialogflow

A lightweight PHP chat service that connects a browser-based frontend to a [Google Cloud Dialogflow CX](https://cloud.google.com/dialogflow/cx/docs) (Vertex AI) conversational agent. It is designed to run on a standard shared PHP hosting environment — no Node.js, no containers, no framework required.

## What it does

The project is a thin, stateless proxy built in vanilla PHP and vanilla HTML/CSS/JS:

- The **frontend** (`public/index.html`, `public/app.js`, `public/style.css`) presents a clean chat window in the browser. Each browser tab generates and persists its own session UUID in `localStorage`, so multiple simultaneous visitors automatically get independent conversations.
- The **backend** (`public/api/chat.php`) receives the user's message and session ID, forwards them to Dialogflow CX via the official [Google Cloud PHP SDK](https://github.com/googleapis/google-cloud-php), and returns the agent's reply as JSON. The browser never touches GCP directly.
- A **CLI tester** (`tools/chat_cli.php`) lets you verify GCP connectivity and credentials from the terminal before opening a browser.

## Getting started

See [`plan.md`](plan.md) for the full, step-by-step setup guide, including:

- Enabling the Dialogflow API and creating a conversational agent in GCP
- Installing dependencies with Composer
- Configuring and deploying to a shared host
- Running the automated test suite

## GCP credentials

This repository does **not** contain any GCP credentials. Two files are required at runtime but are excluded from version control via `.gitignore`:

| File | Purpose |
|---|---|
| `private/gcp-key.json` | Service Account JSON key used to authenticate with GCP |
| `private/config.php` | Your GCP project ID, agent location, and agent UUID |

Both files must be created manually and stored securely outside the repository (e.g. a password manager or encrypted vault). The `private/` directory is also protected at the web-server level so these files are never reachable via a browser.

For full details on how credentials are structured, where to place them, and how the PHP code loads them at runtime, see [Section 1 (GCP Configuration)](plan.md#1-prerequisites-and-gcp-configuration) and [Step 3.1 (Configuration file)](plan.md#step-31-configuration-file-privateconfigphp) in `plan.md`.
