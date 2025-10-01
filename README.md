# Hybrid Conversational RAG Chatbot (Local DB + Gemini LLM)

This project is a hybrid, conversational Retrieval-Augmented Generation (RAG) chatbot. It combines the benefits of a local, customizable knowledge base with the power of a state-of-the-art cloud LLM.

-   **Local Data Retrieval:** It uses a local FAISS vector database built from scraped website content to find relevant information. This means you control the knowledge source.
-   **Cloud-Based Generation:** It uses **Google's Gemini Pro API** to generate high-quality, coherent, and context-aware responses.

The interface is a web-based chat application built with Gradio.

## How it Works

The system is composed of two main parts:

1.  **Data Preparation (`prepare_data.py`):** A script that you run once to scrape content from specified URLs, process the text, create vector embeddings, and save everything into a local FAISS database.
2.  **Chat Application (`app.py`):** The main Gradio application that loads the local vector database. When you ask a question, it retrieves relevant context from your local data and then sends that context, along with the conversation history, to the Google Gemini API to generate a final answer.

## Prerequisites

-   Python 3.7 or higher
-   A Google Gemini API key. You can get one from [Google AI Studio](https://aistudio.google.com/app/apikey).

## Setup and Usage

The setup is a two-step process: first, prepare your local data, and second, run the application.

### Step 1: Prepare the Local Data

This step scrapes websites and builds your local knowledge base. **This step requires an internet connection.**

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/hybrid-rag-chatbot.git
    cd hybrid-rag-chatbot
    ```

2.  **(Optional) Customize URLs:**
    Open `prepare_data.py` and modify the `URLS_TO_SCRAPE` list to include the websites you want the chatbot to be knowledgeable about. By default, it scrapes Wikipedia pages on AI/ML.

3.  **Install Dependencies:**
    Install all the necessary Python packages.
    ```bash
    pip install -r requirements.txt
    ```

4.  **Run the Data Preparation Script:**
    This will scrape the websites, download a sentence-embedding model, and build the vector database.
    ```bash
    python prepare_data.py
    ```
    This process will create two files: `faiss_index.bin` (the vector database) and `text_chunks.pkl` (the raw text for reference).

### Step 2: Run the Chatbot

After the data is prepared, you can run the chatbot application.

1.  **Set up your API Key:**
    Create a file named `.env` in the root of the project directory. Add your Google Gemini API key to this file:
    ```
    GEMINI_API_KEY=your_gemini_api_key
    ```
    Replace `your_gemini_api_key` with your actual key.

2.  **Launch the Application:**
    This step requires an internet connection to communicate with the Gemini API.
    ```bash
    python app.py
    ```
    The script will load your local vector database and configure the Gemini API.

3.  **Access the Chatbot:**
    Once initialized, a local URL will be displayed (e.g., `http://127.0.0.1:7860`). Open this URL in your web browser to start chatting with your RAG assistant. Your questions will be answered by Gemini using the context from your custom, local knowledge base.