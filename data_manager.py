import os
import pickle
import time
import requests
from bs4 import BeautifulSoup
import numpy as np
import faiss
from sentence_transformers import SentenceTransformer
from urllib.parse import urljoin

# --- Configuration ---
KNOWLEDGE_BASE_DIR = "knowledge_bases"
UNIFIED_KB_NAME = "3d_prints_kb"
EMBEDDING_MODEL = 'all-MiniLM-L6-v2'

# Ensure the directory for the knowledge base exists
os.makedirs(KNOWLEDGE_BASE_DIR, exist_ok=True)

# --- Web Scraping Functions for 3D Printing Sites ---
# Note: These selectors are based on the website structures as of late 2025
# and are subject to change. They may need to be updated if the websites are redesigned.

def scrape_thingiverse(base_url="https://www.thingiverse.com/search?q=useful&type=things&sort=popular"):
    """Scrapes popular items from Thingiverse."""
    print(f"Scraping Thingiverse from {base_url}...")
    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = requests.get(base_url, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.content, 'html.parser')

        results = []
        # Find links to individual print pages
        for a_tag in soup.select('div.search-results a.Card__card--thumbnail__1sY9y'):
            title = a_tag.get('title', 'No Title')
            url = urljoin(base_url, a_tag.get('href'))
            results.append({'text': title, 'url': url})
        print(f"Found {len(results)} items from Thingiverse.")
        return results, None
    except Exception as e:
        return None, f"Failed to scrape Thingiverse: {e}"

def scrape_printables(base_url="https://www.printables.com/en/search/models?q=useful&sortBy=popularity"):
    """Scrapes popular items from Printables."""
    print(f"Scraping Printables from {base_url}...")
    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = requests.get(base_url, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.content, 'html.parser')

        results = []
        for a_tag in soup.select('a.link.clamp-2'):
            title = a_tag.text.strip()
            url = urljoin(base_url, a_tag.get('href'))
            results.append({'text': title, 'url': url})
        print(f"Found {len(results)} items from Printables.")
        return results, None
    except Exception as e:
        return None, f"Failed to scrape Printables: {e}"

def scrape_makerworld(base_url="https://makerworld.com/en/search?keyword=useful&sort=popularity"):
    """Scrapes popular items from MakerWorld."""
    print(f"Scraping MakerWorld from {base_url}...")
    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = requests.get(base_url, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.content, 'html.parser')

        results = []
        for a_tag in soup.select('div.card-info-title a'):
            title = a_tag.text.strip()
            url = urljoin(base_url, a_tag.get('href'))
            results.append({'text': title, 'url': url})
        print(f"Found {len(results)} items from MakerWorld.")
        return results, None
    except Exception as e:
        return None, f"Failed to scrape MakerWorld: {e}"

def scrape_creality_cloud(base_url="https://www.crealitycloud.com/model-library?keyword=useful&sort=download"):
    """Scrapes popular items from Creality Cloud."""
    print(f"Scraping Creality Cloud from {base_url}...")
    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = requests.get(base_url, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.content, 'html.parser')

        results = []
        for a_tag in soup.select('div.item-info-main a'):
            title = a_tag.get('title', 'No Title')
            url = urljoin(base_url, a_tag.get('href'))
            results.append({'text': title, 'url': url})
        print(f"Found {len(results)} items from Creality Cloud.")
        return results, None
    except Exception as e:
        return None, f"Failed to scrape Creality Cloud: {e}"

# --- Knowledge Base Building ---
# A mapping from domain to scraper function
SCRAPER_MAPPING = {
    'thingiverse.com': scrape_thingiverse,
    'printables.com': scrape_printables,
    'makerworld.com': scrape_makerworld,
    'crealitycloud.com': scrape_creality_cloud,
}

def build_unified_knowledge_base(urls_to_scrape):
    """
    Scrapes a list of URLs and builds a single, unified knowledge base.
    Each chunk of text is stored with its source URL.
    """
    print("\n--- Building Unified 3D Prints Knowledge Base ---")
    all_scraped_data = []

    # --- 1. Scrape all sources ---
    for url in urls_to_scrape:
        domain = [d for d in SCRAPER_MAPPING if d in url]
        if not domain:
            print(f"Warning: No scraper found for URL: {url}. Skipping.")
            continue

        scraper_func = SCRAPER_MAPPING[domain[0]]
        data, error = scraper_func(url)
        if error:
            print(f"Error scraping {url}: {error}")
            continue
        all_scraped_data.extend(data)

    if not all_scraped_data:
        return False, "Failed to scrape any data. Please check the URLs and website structures."

    # --- 2. Create chunks with source URLs ---
    # In this new design, each scraped item is a "chunk"
    print(f"\nTotal items scraped: {len(all_scraped_data)}")

    # --- 3. Generate embeddings ---
    print(f"Loading sentence transformer model: '{EMBEDDING_MODEL}'...")
    model = SentenceTransformer(EMBEDDING_MODEL)
    print("Generating embeddings for all scraped items... (This can take a while)")

    # Get the text part of our data for embedding
    texts_to_embed = [item['text'] for item in all_scraped_data]

    start_time = time.time()
    embeddings = model.encode(texts_to_embed, show_progress_bar=True)
    end_time = time.time()
    print(f"Embedding generation took {end_time - start_time:.2f} seconds.")

    embeddings = np.array(embeddings).astype('float32')
    d = embeddings.shape[1]

    # --- 4. Create and save FAISS index and data chunks ---
    index = faiss.IndexFlatL2(d)
    index.add(embeddings)

    index_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{UNIFIED_KB_NAME}.bin")
    chunks_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{UNIFIED_KB_NAME}.pkl")

    print(f"Saving FAISS index to '{index_path}'")
    faiss.write_index(index, index_path)

    # Save the structured data (which are our chunks now)
    print(f"Saving structured data chunks to '{chunks_path}'")
    with open(chunks_path, 'wb') as f:
        pickle.dump(all_scraped_data, f)

    success_message = f"✅ Unified knowledge base '{UNIFIED_KB_NAME}' built successfully with {len(all_scraped_data)} items!"
    print(success_message)
    return True, success_message