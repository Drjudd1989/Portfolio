import requests
from bs4 import BeautifulSoup
import re

def format_store_name_for_url(name):
    """Formats a store name to be used in a Rakuten URL."""
    return re.sub(r'[^a-z0-9]', '', name.lower())

def scrape_rakuten(store_name):
    """
    Scrapes Rakuten for cash back offers for a given store.
    """
    formatted_name = format_store_name_for_url(store_name)
    store_url = f"https://www.rakuten.com/shop/{formatted_name}"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }

    try:
        response = requests.get(store_url, headers=headers, timeout=10)
        response.raise_for_status()  # Raises HTTPError for bad responses (4xx or 5xx)
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            return f"Store '{store_name}' not found on Rakuten."
        return f"HTTP error fetching data from Rakuten for '{store_name}': {e}"
    except requests.exceptions.RequestException as e:
        # Handles other network errors (e.g., connection timeout, DNS error)
        return f"Error fetching data from Rakuten for '{store_name}': {e}"

    soup = BeautifulSoup(response.content, "html.parser")

    # Primary Method: Look for a specific attribute used for testing, as it's less likely to change.
    cash_back_element = soup.find(attrs={"data-testid": "cash-back-rate"})
    if cash_back_element:
        cash_back_text = cash_back_element.get_text(strip=True)
        if "%" in cash_back_text:
            return f"Rakuten: {cash_back_text} Cash Back for {store_name}."

    # Fallback 1: Look for an element with text that matches the cash back pattern.
    cash_back_text_node = soup.find(string=re.compile(r'^\s*\d+(\.\d+)?%\s+Cash\s+Back\s*$'))
    if cash_back_text_node:
        return f"Rakuten: {cash_back_text_node.strip()} for {store_name}."

    # Fallback 2: A more general search in the entire page text.
    page_text = soup.get_text()
    match = re.search(r'(\b\d+(\.\d+)?%\s+Cash\s+Back\b)', page_text)
    if match:
        return f"Rakuten: {match.group(1)} for {store_name}."

    return f"No cash back offer found for '{store_name}' on Rakuten."

if __name__ == "__main__":
    # Example usage for testing
    test_stores = ["Macy's", "Saks Fifth Avenue", "Nike", "NonExistentStore123"]
    for store in test_stores:
        print(f"Searching for '{store}'...")
        result = scrape_rakuten(store)
        print(result)