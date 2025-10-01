# Advanced Conversational RAG Chatbot with Admin Portal

This project is an advanced, conversational Retrieval-Augmented Generation (RAG) chatbot that is highly flexible and customizable through a dedicated **Admin Portal**. It uses Google's Gemini Pro for generation and allows you to create and switch between multiple local knowledge bases built from different data sources like **Wikipedia** and **Reddit**.

## Architecture

The system is now split into two distinct applications:

1.  **Admin Portal (`admin_portal.py`):** A web interface for creating and managing your knowledge bases. You can point it at Wikipedia articles or Reddit subreddits, and it will automatically scrape the content and build a vector database for the chatbot to use.
2.  **Chat Application (`app.py`):** The main chat interface. It now includes a dropdown menu to select which of your pre-built knowledge bases you want to chat with, allowing you to switch contexts on the fly.

## Prerequisites

-   Python 3.7 or higher
-   A **Google Gemini API key**. Get one from [Google AI Studio](https://aistudio.google.com/app/apikey).
-   **(Optional) Reddit API Credentials:** If you want to build a knowledge base from Reddit, you will need a Client ID, Client Secret, and User Agent from your Reddit account.

## Setup and Usage

The setup involves installing dependencies and creating a `.env` file for your API keys.

### Step 1: Installation and API Key Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/advanced-rag-chatbot.git
    cd advanced-rag-chatbot
    ```

2.  **Install Dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

3.  **Create and Configure your `.env` file:**
    Create a file named `.env` in the root of the project directory. Add your Gemini API key. If you plan to use Reddit, add your Reddit credentials as well.

    ```env
    # Required for the chatbot
    GEMINI_API_KEY=your_gemini_api_key

    # Required only for building knowledge bases from Reddit
    REDDIT_CLIENT_ID=your_reddit_client_id
    REDDIT_CLIENT_SECRET=your_reddit_client_secret
    REDDIT_USER_AGENT="My RAG Bot v1.0 by u/your_username"
    ```
    Replace the placeholder values with your actual credentials.

### Step 2: Create a Knowledge Base with the Admin Portal

Before you can chat, you need to create at least one knowledge base.

1.  **Launch the Admin Portal:**
    ```bash
    python admin_portal.py
    ```
    Open the local URL provided (e.g., `http://127.0.0.1:7860`) in your browser.

2.  **Build your Knowledge Base:**
    -   **Knowledge Base Name:** Give your KB a simple, file-safe name (e.g., `ai_wiki` or `python_reddit`).
    -   **Select Data Source:** Choose "Wikipedia" or "Reddit".
    -   **Source Input:**
        -   For **Wikipedia**, provide a comma-separated list of article titles (e.g., `Artificial intelligence, Neural network`).
        -   For **Reddit**, provide the name of the subreddit (e.g., `MachineLearning`).
    -   Click **"Build Knowledge Base"**. The process may take a few minutes as it scrapes data and generates embeddings. You can monitor the progress in the log window.

    Your new knowledge base will be saved in the `knowledge_bases/` directory.

### Step 3: Chat with your Knowledge Base

Once you have one or more knowledge bases, you can launch the main chat application.

1.  **Launch the Chat App:**
    ```bash
    python app.py
    ```
    Open the local URL provided in your browser.

2.  **Select and Load:**
    -   The "Select Knowledge Base" dropdown will be populated with the names of the KBs you created.
    -   Choose the one you want to talk to and click **"Load KB"**.

3.  **Start Chatting:**
    Once the status shows that the KB has been loaded successfully, you can start asking questions. The chatbot will use the selected knowledge base to provide context-aware answers from Gemini. You can switch to another knowledge base at any time by selecting it and clicking "Load KB" again.