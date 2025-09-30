import os
import wikipedia
import google.generativeai as genai
import gradio as gr
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Configure the generative AI model
api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    raise ValueError("GEMINI_API_KEY not found in .env file or environment variables.")
genai.configure(api_key=api_key)
model = genai.GenerativeModel('gemini-pro')

def search_wikipedia(query):
    """
    Searches Wikipedia for a given query and returns the content of the most relevant page.
    """
    try:
        # Search for the query on Wikipedia and get the most relevant page title
        page_title = wikipedia.search(query)[0]
        # Get the full page content
        page_content = wikipedia.page(page_title, auto_suggest=False).content
        return page_content
    except (wikipedia.exceptions.PageError, wikipedia.exceptions.DisambiguationError, IndexError):
        return "Could not find any relevant information on Wikipedia for that query."

def conversational_rag_pipeline(message, history):
    """
    The main pipeline for the conversational RAG system.
    Takes a user message and conversation history, retrieves context from Wikipedia,
    and generates a contextual answer.
    """
    # Get context from Wikipedia based on the latest message
    context = search_wikipedia(message)

    # If no context is found, return a specific message
    if "Could not find" in context:
        return context

    # Build a prompt that includes the conversation history and the new context
    prompt_history = ""
    for user_turn, bot_turn in history:
        prompt_history += f"User: {user_turn}\nAssistant: {bot_turn}\n"

    # Construct the full prompt for Gemini
    full_prompt = f"""You are a helpful assistant. Please answer the user's current question based on the provided context from Wikipedia and the ongoing conversation history.

Conversation History:
{prompt_history}

Context from Wikipedia:
"{context}"

Current Question:
{message}
"""

    try:
        # Generate the response from the model
        response = model.generate_content(full_prompt)
        return response.text
    except Exception as e:
        return f"An error occurred while generating the answer: {e}"

# Create the Gradio Chat Interface
iface = gr.ChatInterface(
    fn=conversational_rag_pipeline,
    title="Conversational RAG System with Google Gemini and Wikipedia",
    description="Ask a question, and the system will use Wikipedia to provide a well-informed answer. You can ask follow-up questions.",
    examples=[["What is Retrieval-Augmented Generation?"], ["How does it differ from traditional LLMs?"]],
    chatbot=gr.Chatbot(height=500),
    textbox=gr.Textbox(placeholder="Ask me anything...", container=False, scale=7),
    retry_btn=None,
    undo_btn="Delete Previous Turn",
    clear_btn="Clear Conversation",
).queue()


if __name__ == "__main__":
    iface.launch()