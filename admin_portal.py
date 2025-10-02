import gradio as gr
from dotenv import load_dotenv
import data_manager
import os

# --- Configuration ---
SITES_CONFIG_FILE = "sites_to_scrape.txt"
DEFAULT_SITES = [
    "https://www.thingiverse.com/search?q=useful&type=things&sort=popular",
    "https://www.printables.com/en/search/models?q=useful&sortBy=popularity",
    "https://makerworld.com/en/search?keyword=useful&sort=popularity",
    "https://www.crealitycloud.com/model-library?keyword=useful&sort=download"
]

# --- State Management ---
def load_sites():
    """Loads the list of sites from the config file, or creates it with defaults."""
    if not os.path.exists(SITES_CONFIG_FILE):
        with open(SITES_CONFIG_FILE, 'w') as f:
            for site in DEFAULT_SITES:
                f.write(site + '\n')
        return DEFAULT_SITES
    with open(SITES_CONFIG_FILE, 'r') as f:
        sites = [line.strip() for line in f if line.strip()]
    return sites

def save_sites(sites):
    """Saves the current list of sites to the config file."""
    with open(SITES_CONFIG_FILE, 'w') as f:
        for site in sites:
            f.write(site + '\n')

# --- Gradio Logic ---
def add_new_site(new_site_url, current_sites_text):
    """Adds a new site to the list and saves it."""
    current_sites = [line.strip() for line in current_sites_text.split('\n') if line.strip()]
    if new_site_url and new_site_url not in current_sites:
        current_sites.append(new_site_url)
        save_sites(current_sites)
        return "\n".join(current_sites), f"Added '{new_site_url}'"
    return "\n".join(current_sites), "URL is empty or already in the list."

def run_build_process_for_all(progress=gr.Progress(track_tqdm=True)):
    """Triggers the unified knowledge base building process."""
    progress(0, desc="Loading site list...")
    sites_to_scrape = load_sites()
    if not sites_to_scrape:
        return "Error: No sites configured in 'sites_to_scrape.txt'."

    progress(0.1, desc="Starting build process...")
    is_success, message = data_manager.build_unified_knowledge_base(sites_to_scrape)

    if not is_success:
        return f"Error building knowledge base: {message}"

    return message

# --- Gradio Interface Definition ---
with gr.Blocks(theme=gr.themes.Soft()) as iface:
    gr.Markdown("# 🖨️ 3D Prints Knowledge Base Admin Portal")
    gr.Markdown("Use this portal to manage the list of 3D printing websites and to build the unified knowledge base for the chatbot.")

    with gr.Row():
        with gr.Column(scale=2):
            gr.Markdown("### Manage Scraped Websites")
            sites_list_textbox = gr.Textbox(
                label="Websites to Scrape",
                value="\n".join(load_sites()),
                lines=10,
                interactive=True # Allow editing the whole list
            )

            with gr.Accordion("Add a New Website", open=False):
                new_site_input = gr.Textbox(
                    label="New Site URL",
                    placeholder="e.g., https://www.some-other-site.com/popular"
                )
                add_site_button = gr.Button("Add Site")
                add_site_status = gr.Textbox(label="Status", interactive=False)

            gr.Markdown("---")
            build_button = gr.Button("Build / Update Unified Knowledge Base", variant="primary")

        with gr.Column(scale=3):
            output_textbox = gr.Textbox(
                label="Process Log",
                lines=20,
                interactive=False
            )

    # --- Event Handlers ---
    add_site_button.click(
        fn=add_new_site,
        inputs=[new_site_input, sites_list_textbox],
        outputs=[sites_list_textbox, add_site_status]
    )

    build_button.click(
        fn=run_build_process_for_all,
        inputs=[],
        outputs=output_textbox
    )

if __name__ == "__main__":
    iface.launch()