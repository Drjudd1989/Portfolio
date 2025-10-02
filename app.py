import gradio as gr
import faiss
from sentence_transformers import SentenceTransformer
import pickle
import numpy as np
import google.generativeai as genai
import os
from dotenv import load_dotenv

# --- Configuration ---
KNOWLEDGE_BASE_DIR = "knowledge_bases"
UNIFIED_KB_NAME = "3d_prints_kb"
EMBEDDING_MODEL = 'all-MiniLM-L6-v2'

# --- Global Variables ---
retriever = None
genai_model = None
embedding_model = None # To be loaded once

def initialize_systems():
    """Loads the vector DB, embedding model, and configures the Gemini API."""
    global retriever, genai_model, embedding_model

    print("--- Initializing Systems ---")

    # 1. Load Embedding Model
    print(f"Loading sentence transformer model: '{EMBEDDING_MODEL}'...")
    embedding_model = SentenceTransformer(EMBEDDING_MODEL)

    # 2. Load the Unified Knowledge Base
    print(f"Loading the unified knowledge base: '{UNIFIED_KB_NAME}'...")
    index_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{UNIFIED_KB_NAME}.bin")
    chunks_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{UNIFIED_KB_NAME}.pkl")

    if not os.path.exists(index_path) or not os.path.exists(chunks_path):
        error_msg = f"Knowledge base '{UNIFIED_KB_NAME}' not found. Please run the Admin Portal to build it first."
        print(f"[ERROR] {error_msg}")
        raise gr.Error(error_msg)

    try:
        index = faiss.read_index(index_path)
        with open(chunks_path, 'rb') as f:
            chunks = pickle.load(f)

        retriever = {
            "name": UNIFIED_KB_NAME,
            "index": index,
            "chunks": chunks
        }
        print(f"✅ Knowledge base '{UNIFIED_KB_NAME}' loaded successfully.")
    except Exception as e:
        error_msg = f"An error occurred while loading the knowledge base: {e}"
        print(f"[ERROR] {error_msg}")
        raise gr.Error(error_msg)

    # 3. Configure Google Gemini API
    print("\nConfiguring Google Gemini API...")
    try:
        load_dotenv()
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not found in .env file.")
        genai.configure(api_key=api_key)
        genai_model = genai.GenerativeModel('gemini-pro')
        print("✅ Google Gemini API configured successfully.")
    except Exception as e:
        print(f"\n[ERROR] Failed to configure Gemini API: {e}")
        raise gr.Error("Failed to configure Gemini API. Please check your API key.")

def retrieve_context_from_db(query, k=5):
    """Retrieves relevant items (text and URL) from the vector DB."""
    if not retriever or not embedding_model:
        return "Retriever or embedding model not initialized."

    query_embedding = embedding_model.encode([query]).astype('float32')
    distances, indices = retriever["index"].search(query_embedding, k)

    # Return the full data chunks {text, url}
    retrieved_chunks = [retriever["chunks"][i] for i in indices[0]]

    # Format the context for the LLM
    context_str = "\n".join([f"- {item['text']} (Source: {item['url']})" for item in retrieved_chunks])
    return context_str

def conversational_rag_for_3d_prints(message, history):
    """The main RAG pipeline for the 3D Printing Idea Assistant."""
    if not genai_model:
        return "Error: Gemini model not initialized."
    if not retriever:
        return "Error: The 3D prints knowledge base is not loaded."

    context = retrieve_context_from_db(message)

    prompt_history = ""
    for user_turn, bot_turn in history:
        prompt_history += f"User: {user_turn}\nAssistant: {bot_turn}\n"

    full_prompt = f"""You are a "3D Printing Idea Assistant". Your goal is to help users find interesting and useful things to 3D print.
Based on the user's request and the following list of potential models from your knowledge base, provide a helpful and creative response.

- Brainstorm ideas related to the user's query.
- Suggest specific models from the context provided.
- **ALWAYS include the direct URL to any model you mention.** Format the links using Markdown, like this: [Model Name](URL).
- If the user's request is vague, like "what should I print?", use the context to suggest some popular and interesting items.

Conversation History:
{prompt_history}

Context from Knowledge Base:
{context}

User's Request:
{message}
"""
    try:
        response = genai_model.generate_content(full_prompt)
        return response.text
    except Exception as e:
        return f"An error occurred with the Gemini API: {e}"

# --- Gradio UI ---
with gr.Blocks(theme=gr.themes.Soft()) as iface:
    gr.Markdown("# 🖨️ 3D Printing Idea Assistant")
    gr.Markdown("Ask me for ideas on what to 3D print! For example: 'any ideas for my desk?' or 'show me something useful for the kitchen'.")

    chatbot = gr.Chatbot(height=500, bubble_full_width=False)
    msg = gr.Textbox(placeholder="What are you looking to print today?", container=False, scale=7)
    clear = gr.Button("Clear Conversation")

    msg.submit(conversational_rag_for_3d_prints, [msg, chatbot], chatbot)
    clear.click(lambda: None, None, chatbot, queue=False)

if __name__ == "__main__":
    initialize_systems()
    iface.queue().launch()