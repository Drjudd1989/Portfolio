# 🖨️ 3D Printing Idea Assistant

This project is a conversational RAG (Retrieval-Augmented Generation) chatbot designed to help you discover ideas for 3D printing. It scrapes popular 3D printing websites for models and uses Google's Gemini Pro LLM to provide creative suggestions and direct links to the prints.

## Architecture

The system is composed of two main parts:

1.  **Admin Portal (`admin_portal.py`):** A web interface for managing the list of 3D printing websites that the application will scrape. It comes pre-configured with popular sites and allows you to add more.
2.  **Chat Application (`app.py`):** The main chat interface. It uses a unified knowledge base built by the admin portal to provide you with 3D printing ideas, complete with links to the model pages.

## Features

-   Scrapes popular 3D printing sites like Thingiverse, Printables, MakerWorld, and Creality Cloud.
-   An admin portal to manage the list of scraped websites.
-   A conversational chatbot that provides ideas and direct links to models.
-   Powered by Google's Gemini Pro for high-quality, creative responses.

## Prerequisites

-   Python 3.7 or higher
-   A **Google Gemini API key**. You can get one from [Google AI Studio](https://aistudio.google.com/app/apikey).

## Setup and Usage

The setup is a two-step process: first, build your knowledge base using the Admin Portal, and second, run the main chat application.

### Step 1: Build the Knowledge Base

This step scrapes the configured websites and builds your local knowledge base. **This step requires an internet connection.**

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/3d-print-idea-bot.git
    cd 3d-print-idea-bot
    ```

2.  **Install Dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

3.  **Set up your API Key:**
    Create a file named `.env` in the root of the project directory. Add your Google Gemini API key to this file:
    ```env
    GEMINI_API_KEY=your_gemini_api_key
    ```
    Replace `your_gemini_api_key` with your actual key.

4.  **Launch the Admin Portal:**
    ```bash
    python admin_portal.py
    ```
    Open the local URL provided (e.g., `http://127.0.0.1:7860`) in your browser.

5.  **(Optional) Add More Websites:**
    You can add new URLs to the list in the admin portal. Note that the scraper may need to be updated in `data_manager.py` for websites with different HTML structures.

6.  **Build the Knowledge Base:**
    Click the **"Build / Update Unified Knowledge Base"** button. The process will scrape all configured sites and create a single database. This may take several minutes. You can monitor the progress in the log window.

### Step 2: Chat for Ideas

Once the knowledge base is built, you can launch the main chat application.

1.  **Launch the Chat App:**
    ```bash
    python app.py
    ```
    The application will load the knowledge base and configure the Gemini API. This requires an internet connection.

2.  **Access the Chatbot:**
    Open the local URL provided in your browser.

3.  **Start Chatting:**
    Ask for ideas! For example:
    -   "What should I print for my office?"
    -   "Show me some cool kitchen gadgets."
    -   "I need a gift idea for a friend who likes board games."

The assistant will provide suggestions and include direct, clickable links to the models.