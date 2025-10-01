import gradio as gr
import faiss
from sentence_transformers import SentenceTransformer
import pickle
import numpy as np
import google.generativeai as genai
import os
from dotenv import load_dotenv

# --- Configuration ---
FAISS_INDEX_PATH = "faiss_index.bin"
TEXT_CHUNKS_PATH = "text_chunks.pkl"
EMBEDDING_MODEL = 'all-MiniLM-L6-v2'

# --- Global Variables ---
retriever = None
genai_model = None

def initialize_systems():
    """Loads all necessary models and data."""
    global retriever, genai_model

    print("--- Initializing Systems ---")

    # 1. Load Local Vector DB and Text Chunks
    print("Loading local vector database...")
    if not os.path.exists(FAISS_INDEX_PATH) or not os.path.exists(TEXT_CHUNKS_PATH):
        print("\n[ERROR] Vector database not found!")
        print(f"Please run 'python prepare_data.py' first to create the database.")
        raise gr.Error("Vector database not found. Please run 'python prepare_data.py' first.")

    index = faiss.read_index(FAISS_INDEX_PATH)
    with open(TEXT_CHUNKS_PATH, 'rb') as f:
        text_chunks = pickle.load(f)

    # 2. Load Embedding Model for retrieval
    print(f"Loading sentence transformer model: '{EMBEDDING_MODEL}'...")
    embedding_model = SentenceTransformer(EMBEDDING_MODEL)

    # 3. Create Retriever object
    retriever = {
        "index": index,
        "model": embedding_model,
        "chunks": text_chunks
    }
    print("Vector database and retriever are ready.")

    # 4. Configure Google Gemini API
    print("\nConfiguring Google Gemini API...")
    try:
        load_dotenv()
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not found in .env file or environment variables.")
        genai.configure(api_key=api_key)
        genai_model = genai.GenerativeModel('gemini-pro')
        print("✅ Google Gemini API configured successfully.")
    except Exception as e:
        print(f"\n[ERROR] Failed to configure Gemini API: {e}")
        raise gr.Error(f"Failed to configure Gemini API. Please check your API key and see console for details.")

    print("\n--- All systems initialized. Application is ready. ---")

def retrieve_context_from_db(query, k=3):
    """Retrieves relevant text chunks from the local vector DB based on the query."""
    if not retriever:
        return "Retriever not initialized."

    query_embedding = retriever["model"].encode([query]).astype('float32')
    distances, indices = retriever["index"].search(query_embedding, k)

    # Get the actual text chunks
    retrieved_chunks = [retriever["chunks"][i] for i in indices[0]]
    return "\n---\n".join(retrieved_chunks)

def conversational_rag_with_gemini(message, history):
    """
    The main RAG pipeline using a local DB for retrieval and Gemini for generation.
    """
    if not genai_model:
        return "Gemini model not initialized. Please check the console for errors."

    # 1. Retrieve context from the local DB
    context = retrieve_context_from_db(message)

    # 2. Build conversation history string
    prompt_history = ""
    for user_turn, bot_turn in history:
        prompt_history += f"User: {user_turn}\nAssistant: {bot_turn}\n"

    # 3. Construct the prompt for Gemini
    full_prompt = f"""You are a helpful assistant. Please answer the user's current question based on the provided context from your local knowledge base and the ongoing conversation history.

Conversation History:
{prompt_history}

Local Knowledge Base Context:
"{context}"

Current Question:
{message}
"""

    try:
        # 4. Generate response from Gemini
        response = genai_model.generate_content(full_prompt)
        return response.text
    except Exception as e:
        return f"An error occurred while communicating with the Gemini API: {e}"

# --- Gradio UI ---
with gr.Blocks(theme=gr.themes.Soft()) as iface:
    gr.Markdown("# 🤖 Conversational RAG Chatbot (Local DB + Gemini LLM)")
    gr.Markdown(
        "This chatbot uses a **local vector database** (built from scraped websites) for information retrieval "
        "and **Google's Gemini Pro** for response generation. "
        "Run `prepare_data.py` to build the local database."
    )

    chatbot = gr.Chatbot(height=500)
    msg = gr.Textbox(placeholder="Ask a question about the scraped content...", container=False, scale=7)
    clear = gr.Button("Clear Conversation")

    msg.submit(conversational_rag_with_gemini, [msg, chatbot], chatbot)
    clear.click(lambda: None, None, chatbot, queue=False)

if __name__ == "__main__":
    initialize_systems()
    iface.queue().launch()