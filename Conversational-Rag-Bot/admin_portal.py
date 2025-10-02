import gradio as gr
from dotenv import load_dotenv
import data_manager
import re

# Load environment variables for API keys
load_dotenv()

def sanitize_filename(name):
    """Removes special characters to create a safe filename."""
    return re.sub(r'[^a-zA-Z0-9_\-]', '', name)

def run_build_process(source_type, source_input, kb_name, progress=gr.Progress(track_tqdm=True)):
    """The main function to trigger the data fetching and knowledge base building process."""

    # --- 1. Input Validation ---
    progress(0, desc="Validating inputs...")
    if not kb_name or not source_input:
        return "Error: Please provide both a Knowledge Base Name and a Source Input."

    sanitized_kb_name = sanitize_filename(kb_name)
    if not sanitized_kb_name:
        return "Error: Knowledge Base Name contains invalid characters. Please use letters, numbers, hyphens, or underscores."

    # --- 2. Fetch Content ---
    text_content = None
    error_message = None

    progress(0.2, desc=f"Fetching data from {source_type}...")
    if source_type == "Wikipedia":
        # Split by comma and strip whitespace for multiple articles
        articles = [title.strip() for title in source_input.split(',')]
        text_content, error_message = data_manager.fetch_wikipedia_content(articles)
    elif source_type == "Reddit":
        text_content, error_message = data_manager.fetch_reddit_content(source_input)
    else:
        return "Error: Invalid source type selected."

    if error_message:
        return f"Error fetching data: {error_message}"
    if not text_content:
        return "Error: No content was fetched. Please check your inputs and try again."

    # --- 3. Build Knowledge Base ---
    progress(0.6, desc="Building knowledge base... (This may take a while)")
    is_success, message = data_manager.build_knowledge_base(sanitized_kb_name, text_content)

    if not is_success:
        return f"Error building knowledge base: {message}"

    return message

# --- Gradio Interface Definition ---
with gr.Blocks(theme=gr.themes.Soft()) as iface:
    gr.Markdown("# 📚 Knowledge Base Admin Portal")
    gr.Markdown("Use this portal to create new knowledge bases for your RAG chatbot from different data sources.")

    with gr.Row():
        with gr.Column(scale=2):
            kb_name_input = gr.Textbox(
                label="Knowledge Base Name",
                placeholder="e.g., 'ai_research_wiki' or 'python_help_reddit'"
            )
            source_type_dropdown = gr.Dropdown(
                label="Select Data Source",
                choices=["Wikipedia", "Reddit"],
                value="Wikipedia"
            )
            source_input_textbox = gr.Textbox(
                label="Source Input",
                placeholder="For Wikipedia: 'Artificial Intelligence, Machine Learning', For Reddit: 'python'"
            )
            build_button = gr.Button("Build Knowledge Base", variant="primary")

        with gr.Column(scale=3):
            output_textbox = gr.Textbox(
                label="Process Log",
                lines=15,
                interactive=False
            )

    gr.Markdown(
        "**Note on Reddit:** Ensure your `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET`, and `REDDIT_USER_AGENT` "
        "are set in your `.env` file to fetch data from Reddit."
    )

    build_button.click(
        fn=run_build_process,
        inputs=[source_type_dropdown, source_input_textbox, kb_name_input],
        outputs=output_textbox
    )

if __name__ == "__main__":
    iface.launch()