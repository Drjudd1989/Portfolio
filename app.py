import gradio as gr
import faiss
from sentence_transformers import SentenceTransformer
import pickle
import numpy as np
from transformers import pipeline, AutoTokenizer, AutoModelForCausalLM
from transformers.pipelines.conversational import Conversation
import os

# --- Configuration ---
FAISS_INDEX_PATH = "faiss_index.bin"
TEXT_CHUNKS_PATH = "text_chunks.pkl"
EMBEDDING_MODEL = 'all-MiniLM-L6-v2'
# Switched to a model fine-tuned for dialogue for better conversational quality.
LOCAL_LLM_MODEL = "microsoft/DialoGPT-medium"

# --- Global Variables ---
retriever = None
llm_pipeline = None

def initialize_offline_systems():
    """Loads all necessary models and data for offline use."""
    global retriever, llm_pipeline

    print("--- Initializing Offline Systems ---")

    # 1. Load Vector DB and Text Chunks
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

    # 4. Load Local Conversational LLM
    print(f"\nLoading local LLM for conversation: '{LOCAL_LLM_MODEL}'...")
    print("This may take some time and download the model if not cached.")
    try:
        # Use the 'conversational' pipeline for chatbot-like interactions
        llm_pipeline = pipeline('conversational', model=LOCAL_LLM_MODEL)
        print("✅ Local conversational LLM loaded successfully.")
    except Exception as e:
        print(f"\n[ERROR] Failed to load the local LLM: {e}")
        print("Please ensure you have a stable internet connection for the initial download,")
        print("and that you have 'torch' and 'transformers' installed correctly.")
        raise gr.Error(f"Failed to load local LLM: {LOCAL_LLM_MODEL}. See console for details.")

    print("\n--- All systems initialized. Application is ready. ---")

def retrieve_context(query, k=2):
    """Retrieves relevant text chunks from the vector DB based on the query."""
    if not retriever:
        return "Retriever not initialized."

    query_embedding = retriever["model"].encode([query]).astype('float32')
    distances, indices = retriever["index"].search(query_embedding, k)

    # Get the actual text chunks
    retrieved_chunks = [retriever["chunks"][i] for i in indices[0]]
    return "\n---\n".join(retrieved_chunks)

def conversational_offline_rag(message, history):
    """
    The main RAG pipeline for the offline conversational chatbot.
    This version uses a proper conversational pipeline.
    """
    if not llm_pipeline:
        return "LLM not initialized. Please check the console for errors."

    # 1. Retrieve context from the local DB based on the user's latest message
    context = retrieve_context(message)

    # 2. Inject the context into the conversation.
    # We prepend the context to the user's message to guide the model.
    # This is a simple but effective way to ground the model's response.
    contextual_message = f"""Based on the following context, answer the user's question.
Context: "{context}"

Question: {message}
"""

    # 3. Use the conversational pipeline, providing the history
    # The pipeline manages the conversation object internally.
    # We build the conversation turn by turn from the history provided by Gradio.
    conversation = Conversation()
    for user_turn, bot_turn in history:
        conversation.add_user_input(user_turn)
        conversation.mark_processed() # Mark the user input as processed
        conversation.append_response(bot_turn)

    # Add the new user message (with context) to the conversation
    conversation.add_user_input(contextual_message)

    # Get the model's response
    result = llm_pipeline(conversation)

    # The pipeline returns the entire conversation object. We need the last response.
    return result.generated_responses[-1]

# --- Gradio UI ---
with gr.Blocks(theme=gr.themes.Soft()) as iface:
    gr.Markdown("# 🤖 Fully Offline Conversational RAG Chatbot")
    gr.Markdown(
        "This chatbot uses a local vector database (from scraped websites) and a local LLM (`microsoft/DialoGPT-medium`) to answer your questions. "
        "It is fully offline after the initial setup. Run `python prepare_data.py` to build the database."
    )

    chatbot = gr.Chatbot(height=500)
    msg = gr.Textbox(placeholder="Ask a question about the scraped content...", container=False, scale=7)
    clear = gr.Button("Clear Conversation")

    msg.submit(conversational_offline_rag, [msg, chatbot], chatbot)
    clear.click(lambda: None, None, chatbot, queue=False)

if __name__ == "__main__":
    initialize_offline_systems()
    iface.queue().launch()