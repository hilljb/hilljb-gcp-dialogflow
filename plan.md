# Development Plan: PHP Dialogflow CX (Vertex AI) Chat Service

This plan was created via Gemini for creating the link between the frontend webpage and Vertex AI. I will modify with notes where needed for those wishing to follow along.

This document outlines the plan for developing and testing a frontend website that interacts with a PHP backend to communicate with a Google Cloud Dialogflow CX (Vertex AI) agent. The architecture is designed to support multiple concurrent user sessions on a shared PHP server.

## 1. Prerequisites and GCP Configuration
Before writing code, the Google Cloud environment must be prepared to allow the shared server to authenticate and communicate with Dialogflow CX.

*   **GCP Project & API:** Ensure a Google Cloud Project is created and the **Dialogflow API** is enabled.
    *   You don't need to use the "Create credentials" button after enabling the API. We'll add auth through a service account.
*   **Create a Conversational Agent:**
    *   This is different than what I've done before: Use the GCP Agents Platform to manually train a RAG agent. This should be easier, and hopefully cheaper.
    *   Open the [Conversational Agents Console](https://conversational-agents.cloud.google.com/)
    *   Create an agent. Use the "Build your own" option. Note the details, such as location (mine: `us-central1`). Use the "Playbook" option.
    *   This is where you'll do things like use a datastore, such as a GCP bucket, to specially train the model. For now, we'll just make something via prompting. Do whatever you want.
    *   You can enable logging here, send to BigQuery, etc. to examine chat history.
*   **Service Account Authentication:**
    *   Create a Service Account in GCP.
    *   Assign it the **Dialogflow Client** role (least privilege required to detect intent).
    *   Generate a JSON key for this Service Account.
    *   **Security Note for Shared Server:** This JSON file must be securely uploaded to the shared server, ideally *outside* the public web root (e.g., `/home/username/private/gcp-key.json`) so it cannot be accessed via a web browser.

## 2. Project Setup & Dependencies
Set up the PHP environment and install the required Google Cloud client libraries.

*   **Composer Initialization:** Initialize a `composer.json` file in the project root.
*   **Install Google Cloud PHP SDK:** Run `composer require google/cloud-dialogflow-cx`.
*   **Directory Structure:**
    ```text
    / (Project Root)
    ├── composer.json
    ├── vendor/                 # Composer dependencies
    ├── public/                 # Web root (if applicable)
    │   ├── index.html          # Frontend UI
    │   ├── app.js              # Frontend logic
    │   ├── style.css           # Basic styling
    │   └── api/
    │       └── chat.php        # PHP Backend Endpoint
    └── private/
        └── gcp-key.json        # Service Account Key (Keep secure!)
    ```

## 3. Backend Development (PHP)
The PHP backend acts as a secure proxy between the frontend and Google Cloud, managing authentication and user sessions.

*   **Session Management:**
    *   Use PHP's built-in session handling (`session_start()`) to generate and maintain a unique Session ID for each user. Dialogflow CX requires a `Session ID` to maintain conversation context.
    *   Alternatively, generate a UUID on the frontend, store it in `localStorage`, and pass it in every request to the PHP backend. (This is often more robust for stateless API designs).
*   **Authentication:**
    *   Configure the Dialogflow CX client to use the Service Account JSON key. This can be done by setting the `GOOGLE_APPLICATION_CREDENTIALS` environment variable in PHP (`putenv()`) or passing the credentials directly to the client constructor.
*   **The `chat.php` Endpoint:**
    *   Accept POST requests containing the user's message (JSON format).
    *   Extract the user's message and the Session ID.
    *   Construct a `DetectIntentRequest` using the `google/cloud-dialogflow-cx` library.
    *   Send the request to the Dialogflow CX API.
    *   Parse the `DetectIntentResponse` to extract the agent's text reply.
    *   Return the reply as a JSON response to the frontend.
    *   **Error Handling:** Implement `try/catch` blocks to handle GCP API errors, missing credentials, or invalid input, returning appropriate HTTP status codes (e.g., 400, 500).

## 4. Frontend Development (HTML/JS)
A basic, lightweight frontend to interact with the PHP backend.

*   **UI (`index.html` & `style.css`):**
    *   A scrollable chat window to display the conversation history.
    *   An input text field for the user's message.
    *   A "Send" button (and "Enter" key listener).
*   **Logic (`app.js`):**
    *   Maintain the chat UI state (appending user messages and bot responses to the DOM).
    *   Use the `fetch()` API to send asynchronous POST requests to `chat.php`.
    *   Handle loading states (e.g., showing a "typing..." indicator while waiting for the PHP backend).
    *   Manage the Session ID (if using the frontend-generated UUID approach) by checking `localStorage` on load and generating one if it doesn't exist.

## 5. Testing Strategy

### Phase 5.1: Local Testing
*   Use PHP's built-in web server (`php -S localhost:8000 -t public/`) to test the application locally.
*   Verify that the `chat.php` endpoint successfully communicates with GCP using the local path to the JSON key.
*   Test basic conversation flow in the browser.

### Phase 5.2: Concurrency & Session Testing
*   Open the frontend in multiple different browsers (e.g., Chrome, Firefox) or use Incognito/Private windows simultaneously.
*   Send different messages in each window.
*   **Verification:** Ensure that Dialogflow CX treats them as separate conversations (e.g., context from Browser A does not bleed into Browser B). This confirms the Session ID logic is working correctly.

### Phase 5.3: Shared Server Deployment & Testing
*   Deploy the code to the shared hosting environment (via FTP, SSH, or Git).
*   **Crucial Security Check:** Attempt to access the `gcp-key.json` file directly via the web browser (e.g., `https://yourdomain.com/private/gcp-key.json`). Ensure it returns a 403 Forbidden or 404 Not Found error. If it is accessible, move it outside the `public_html` directory or secure it with `.htaccess`.
*   Test the live URL to ensure the PHP environment has the necessary extensions (like cURL, JSON, and gRPC/Protobuf if required by the Google Cloud SDK) and can successfully reach the outside internet to contact GCP.

## 6. Future Enhancements (Post-MVP)
*   **Styling:** Upgrade the basic UI with a modern CSS framework (Tailwind, Bootstrap) or custom CSS.
*   **Rich Responses:** Handle Dialogflow CX rich responses (buttons, links, custom payloads) in the PHP parser and frontend UI.
*   **Logging:** Implement a logging mechanism in PHP to track API latency, errors, and usage for debugging on the shared server.
*   **Rate Limiting:** Add basic rate limiting to `chat.php` to prevent abuse of the GCP API quota.