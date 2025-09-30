# Fully Offline Conversational RAG Chatbot

This project is a fully offline, conversational Retrieval-Augmented Generation (RAG) chatbot. It uses a local vector database built from scraped website content and a local Large Language Model (LLM) to function without any internet connection after the initial setup.

The interface is a web-based chat application built with Gradio. This version has been corrected to use a proper conversational pipeline for higher quality responses.

## How it Works

The system is composed of two main parts:

1.  **Data Preparation (`prepare_data.py`):** A script that you run once to scrape content from specified URLs, process the text, create vector embeddings using Sentence-Transformers, and save everything into a local FAISS database.
2.  **Chat Application (`app.py`):** The main Gradio application that loads the local vector database and a local conversational LLM (`microsoft/DialoGPT-medium`). When you ask a question, it retrieves relevant context from the database and injects it into the conversation to generate a fact-grounded answer with the local LLM.

## Prerequisites

- Python 3.7 or higher
- `git` and `git-lfs` (recommended for downloading language models)

## Setup and Usage

The setup is a two-step process: first, prepare the data, and second, run the application.

### Step 1: Prepare the Data

This step scrapes websites and builds your local knowledge base. **This step requires an internet connection.**

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/offline-rag-chatbot.git
    cd offline-rag-chatbot
    ```

2.  **(Optional) Customize URLs:**
    Open `prepare_data.py` and modify the `URLS_TO_SCRAPE` list to include the websites you want the chatbot to be knowledgeable about.

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

### Step 2: Run the Offline Chatbot

After the data is prepared, you can run the chatbot. **The very first time you run this, it will download the local LLM, which requires an internet connection.** After that, it will be fully offline.

1.  **Launch the Application:**
    ```bash
    python app.py
    ```
    The script will load the vector database and download/load the local conversational LLM (`microsoft/DialoGPT-medium`). This might take some time and memory, especially on the first run.

2.  **Access the Chatbot:**
    Once the models are loaded, a local URL will be displayed (e.g., `http://127.0.0.1:7860`). Open this URL in your web browser to start chatting with your offline RAG assistant.

## How the Correction Improved the Chatbot

The previous version used a base text-generation model with a complex prompt, which resulted in incoherent responses. This version has been fixed by:
- **Using a Conversational Model:** Switching to `microsoft/DialoGPT-medium`, a model specifically fine-tuned for dialogue.
- **Using the Correct Pipeline:** Employing the `conversational` pipeline from the `transformers` library, which correctly manages chat history and context.
- **Improved Context Injection:** The retrieved context is now cleanly prepended to the user's question, guiding the model more effectively without confusing it.

These changes result in a much more functional and coherent chatbot.