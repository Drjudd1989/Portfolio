import os
import pickle
import time
import praw
import requests
from bs4 import BeautifulSoup
import numpy as np
import faiss
from sentence_transformers import SentenceTransformer

# --- Configuration ---
KNOWLEDGE_BASE_DIR = "knowledge_bases"
EMBEDDING_MODEL = 'all-MiniLM-L6-v2'
TEXT_CHUNK_SIZE = 512  # Characters

# Ensure the directory for knowledge bases exists
os.makedirs(KNOWLEDGE_BASE_DIR, exist_ok=True)

# --- Reddit API Fetching ---
def get_reddit_client():
    """Initializes and returns a PRAW Reddit client using credentials from environment variables."""
    try:
        reddit = praw.Reddit(
            client_id=os.getenv("REDDIT_CLIENT_ID"),
            client_secret=os.getenv("REDDIT_CLIENT_SECRET"),
            user_agent=os.getenv("REDDIT_USER_AGENT"),
        )
        reddit.read_only = True
        return reddit
    except Exception as e:
        print(f"Failed to initialize Reddit client: {e}")
        return None

def fetch_reddit_content(subreddit_name, post_limit=50):
    """Fetches text content from a specified subreddit."""
    print(f"--- Fetching content from r/{subreddit_name} ---")
    reddit = get_reddit_client()
    if not reddit:
        return None, "Failed to initialize Reddit client. Check credentials."

    all_text = ""
    try:
        subreddit = reddit.subreddit(subreddit_name)
        # Fetch top posts from the last month
        for post in subreddit.top(time_filter="month", limit=post_limit):
            all_text += post.title + "\n"
            all_text += post.selftext + "\n"
            # Fetch top comments from each post
            post.comments.replace_more(limit=0)
            for comment in post.comments.list()[:5]: # Top 5 comments
                all_text += comment.body + "\n"
        return all_text, None
    except Exception as e:
        error_message = f"An error occurred while fetching from r/{subreddit_name}: {e}"
        print(error_message)
        return None, error_message

# --- Wikipedia API Fetching ---
def fetch_wikipedia_content(article_titles):
    """Fetches text content from a list of Wikipedia article titles."""
    print(f"--- Fetching content from Wikipedia for: {article_titles} ---")
    all_text = ""
    for title in article_titles:
        try:
            url = f"https://en.wikipedia.org/wiki/{title.strip().replace(' ', '_')}"
            response = requests.get(url)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            content_div = soup.find(id="content")
            if content_div:
                paragraphs = content_div.find_all('p')
                for p in paragraphs:
                    all_text += p.get_text() + "\n"
        except requests.exceptions.RequestException as e:
            error_message = f"Error scraping Wikipedia article '{title}': {e}"
            print(error_message)
            return None, error_message
    return all_text, None

# --- Knowledge Base Building ---
def create_text_chunks(text, chunk_size):
    """Splits a large text into smaller, non-overlapping chunks."""
    print("\n--- Creating Text Chunks ---")
    chunks = [text[i:i+chunk_size] for i in range(0, len(text), chunk_size)]
    print(f"Created {len(chunks)} chunks of approximately {chunk_size} characters each.")
    return chunks

def build_knowledge_base(source_name, text_content):
    """Creates embeddings and saves a FAISS index and text chunks for a given source."""
    if not text_content or not text_content.strip():
        return None, "No text content provided to build the knowledge base."

    print(f"\n--- Building Knowledge Base for: {source_name} ---")

    # 1. Create text chunks
    chunks = create_text_chunks(text_content, TEXT_CHUNK_SIZE)

    # 2. Generate embeddings
    print(f"Loading sentence transformer model: '{EMBEDDING_MODEL}'...")
    model = SentenceTransformer(EMBEDDING_MODEL)
    print("Generating embeddings... (This can take a while)")
    start_time = time.time()
    embeddings = model.encode(chunks, show_progress_bar=True)
    end_time = time.time()
    print(f"Embedding generation took {end_time - start_time:.2f} seconds.")

    embeddings = np.array(embeddings).astype('float32')
    d = embeddings.shape[1]

    # 3. Create and save FAISS index
    index = faiss.IndexFlatL2(d)
    index.add(embeddings)

    index_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{source_name}.bin")
    chunks_path = os.path.join(KNOWLEDGE_BASE_DIR, f"{source_name}.pkl")

    print(f"Saving FAISS index to '{index_path}'")
    faiss.write_index(index, index_path)

    # 4. Save the text chunks
    print(f"Saving text chunks to '{chunks_path}'")
    with open(chunks_path, 'wb') as f:
        pickle.dump(chunks, f)

    success_message = f"✅ Knowledge base '{source_name}' built successfully!"
    print(success_message)
    return True, success_message