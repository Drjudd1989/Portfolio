import requests
from bs4 import BeautifulSoup
import numpy as np
import faiss
from sentence_transformers import SentenceTransformer
import pickle
import time

# --- Configuration ---
# You can replace these URLs with any websites you want to scrape.
URLS_TO_SCRAPE = [
    "https://en.wikipedia.org/wiki/Artificial_intelligence",
    "https://en.wikipedia.org/wiki/Machine_learning",
    "https://en.wikipedia.org/wiki/Deep_learning"
]
TEXT_CHUNK_SIZE = 512  # Size of text chunks in characters
FAISS_INDEX_PATH = "faiss_index.bin"
TEXT_CHUNKS_PATH = "text_chunks.pkl"
EMBEDDING_MODEL = 'all-MiniLM-L6-v2' # A good, lightweight sentence transformer

def scrape_urls(urls):
    """Scrapes text content from a list of URLs."""
    print("--- Starting URL Scraping ---")
    all_text = ""
    for url in urls:
        try:
            print(f"Scraping {url}...")
            response = requests.get(url)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Find the main content area of the page to be more targeted
            content_div = soup.find(id="content")
            if content_div:
                paragraphs = content_div.find_all('p')
                for p in paragraphs:
                    all_text += p.get_text() + "\n"
            else: # Fallback for pages without a "content" id
                all_text += soup.get_text()

        except requests.exceptions.RequestException as e:
            print(f"Error scraping {url}: {e}")
    print("--- Scraping Complete ---")
    return all_text

def create_text_chunks(text, chunk_size):
    """Splits a large text into smaller, non-overlapping chunks."""
    print("\n--- Creating Text Chunks ---")
    chunks = [text[i:i+chunk_size] for i in range(0, len(text), chunk_size)]
    print(f"Created {len(chunks)} chunks of approximately {chunk_size} characters each.")
    return chunks

def create_and_save_embeddings(text_chunks):
    """Creates embeddings for text chunks and saves them to a FAISS index."""
    print("\n--- Creating and Saving Embeddings ---")
    print(f"Loading sentence transformer model: '{EMBEDDING_MODEL}'...")
    print("This may download the model if it's not already cached.")
    model = SentenceTransformer(EMBEDDING_MODEL)

    print("\nGenerating embeddings for text chunks... (This may take a while depending on the amount of text)")
    start_time = time.time()
    embeddings = model.encode(text_chunks, show_progress_bar=True)
    end_time = time.time()
    print(f"Embedding generation took {end_time - start_time:.2f} seconds.")

    embeddings = np.array(embeddings).astype('float32')
    d = embeddings.shape[1]

    print("\nCreating FAISS index...")
    index = faiss.IndexFlatL2(d)
    index.add(embeddings)

    print(f"Saving FAISS index to '{FAISS_INDEX_PATH}'")
    faiss.write_index(index, FAISS_INDEX_PATH)

    print(f"Saving text chunks to '{TEXT_CHUNKS_PATH}'")
    with open(TEXT_CHUNKS_PATH, 'wb') as f:
        pickle.dump(text_chunks, f)

    print("--- Data Preparation Complete ---")

def main():
    """Main function to run the data preparation pipeline."""
    scraped_text = scrape_urls(URLS_TO_SCRAPE)
    if not scraped_text.strip():
        print("No text was scraped. Please check the URLs and your internet connection. Exiting.")
        return

    chunks = create_text_chunks(scraped_text, TEXT_CHUNK_SIZE)
    create_and_save_embeddings(chunks)

    print(f"\n✅ Successfully created and saved the vector database ('{FAISS_INDEX_PATH}') and text chunks ('{TEXT_CHUNKS_PATH}').")
    print("You can now run the main application using: python app.py")

if __name__ == "__main__":
    main()