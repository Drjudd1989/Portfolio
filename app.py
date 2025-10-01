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
EMBEDDING_MODEL = 'all-MiniLM-L6-v2'

# --- Global Variables ---
# This will hold the currently loaded retriever
retriever = None
genai_model = None
# Pre-load the embedding model once to speed up retriever loading
embedding_model = SentenceTransformer(EMBEDDING_MODEL)

def get_available_knowledge_bases():
    """Scans the knowledge base directory and returns a list of available KB names."""
    if not os.path.exists(KNOWLEDGE_BASE_DIR):
        return []
    # A knowledge base is valid if both its .bin (index) and .pkl (chunks) files exist
    files = os.listdir(KNOWLEDGE_BASE_DIR)
    # Get the base names without extension
    base_names = list(set([f.split('.')[0] for f in files]))
    valid_kbs = [
        name for name in base_names
        if f"{name}.bin" in files and f"{name}.pkl" in files
    ]
    return valid_kbs

def load_knowledge_base(kb_name):
    """Loads a specific knowledge base (FAISS index and text chunks) into memory."""
    global retriever
    print(f"--- Loading Knowledge Base: {kb_name} ---")

    index_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{kb_name}.bin")
    chunks_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{kb_name}.pkl")

    if not os.path.exists(index_path) or not os.path.exists(chunks_path):
        error_msg = f"Error: Knowledge base '{kb_name}' is not found or is incomplete."
        print(error_msg)
        # We'll return an error message to be displayed in the UI
        return error_msg

    try:
        index = faiss.read_index(index_path)
        with open(chunks_path, 'rb') as f:
            chunks = pickle.load(f)

        retriever = {
            "name": kb_name,
            "index": index,
            "chunks": chunks
        }
        success_msg = f"✅ Successfully loaded knowledge base: '{kb_name}'"
        print(success_msg)
        return success_msg
    except Exception as e:
        error_msg = f"An error occurred while loading '{kb_name}': {e}"
        print(error_msg)
        retriever = None # Reset retriever on failure
        return error_msg

def retrieve_context_from_db(query, k=3):
    """Retrieves relevant text chunks from the currently loaded vector DB."""
    if not retriever:
        return "Please select and load a knowledge base first."

    # Use the globally pre-loaded embedding model
    query_embedding = embedding_model.encode([query]).astype('float32')
    distances, indices = retriever["index"].search(query_embedding, k)

    retrieved_chunks = [retriever["chunks"][i] for i in indices[0]]
    return "\n---\n".join(retrieved_chunks)

def conversational_rag_with_gemini(message, history):
    """The main RAG pipeline using a selected local DB and Gemini."""
    if not genai_model:
        return "Error: Gemini model not initialized. Check API key."
    if not retriever:
        # This will be shown in the chatbot window if no KB is loaded
        return "Error: No knowledge base has been loaded. Please select one from the dropdown and click 'Load'."

    context = retrieve_context_from_db(message)

    prompt_history = ""
    for user_turn, bot_turn in history:
        prompt_history += f"User: {user_turn}\nAssistant: {bot_turn}\n"

    full_prompt = f"""You are a helpful assistant. Please answer the user's current question based on the provided context from the '{retriever['name']}' knowledge base and the ongoing conversation history.

Conversation History:
{prompt_history}

Knowledge Base Context:
"{context}"

Current Question:
{message}
"""
    try:
        response = genai_model.generate_content(full_prompt)
        return response.text
    except Exception as e:
        return f"An error occurred with the Gemini API: {e}"

# --- System Initialization ---
def initialize_gemini():
    """Configures the Google Gemini API."""
    global genai_model
    print("\n--- Configuring Google Gemini API ---")
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
        # This error will be visible on the console
        raise gr.Error("Failed to configure Gemini API. Please check your API key and see console for details.")

# --- Gradio UI ---
with gr.Blocks(theme=gr.themes.Soft()) as iface:
    gr.Markdown("# 🤖 Advanced RAG Chatbot (Multiple KBs + Gemini)")
    gr.Markdown("Select a knowledge base, load it, and then start chatting.")

    with gr.Row():
        kb_dropdown = gr.Dropdown(
            label="Select Knowledge Base",
            choices=get_available_knowledge_bases()
        )
        load_kb_button = gr.Button("Load KB")
        status_textbox = gr.Textbox(label="Status", interactive=False)

    chatbot = gr.Chatbot(height=450)
    msg = gr.Textbox(placeholder="Ask a question about the loaded knowledge base...", container=False, scale=7)
    clear = gr.Button("Clear Conversation")

    # Wire up the UI components
    load_kb_button.click(
        fn=load_knowledge_base,
        inputs=[kb_dropdown],
        outputs=[status_textbox]
    )
    msg.submit(conversational_rag_with_gemini, [msg, chatbot], chatbot)
    clear.click(lambda: None, None, chatbot, queue=False)

if __name__ == "__main__":
    initialize_gemini()
    iface.queue().launch()