import tkinter as tk
from tkinter import ttk
import threading
import webbrowser
from scraper import scrape_rakuten, format_store_name_for_url

class CashbackApp(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("Cash Back Finder")
        self.geometry("800x600")

        # Tab control
        self.tabControl = ttk.Notebook(self)

        self.tab1 = ttk.Frame(self.tabControl)
        self.tab2 = ttk.Frame(self.tabControl)

        self.tabControl.add(self.tab1, text='Store Search')
        self.tabControl.add(self.tab2, text='Credit Card Offers')
        self.tabControl.pack(expand=1, fill="both")

        self.setup_store_search_tab()
        self.setup_credit_card_offers_tab()

    def setup_store_search_tab(self):
        # Main frame
        main_frame = ttk.Frame(self.tab1, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Search frame
        search_frame = ttk.Frame(main_frame)
        search_frame.pack(fill=tk.X, pady=5)

        self.search_label = ttk.Label(search_frame, text="Store Name:")
        self.search_label.pack(side=tk.LEFT, padx=5)

        self.search_entry = ttk.Entry(search_frame, width=50)
        self.search_entry.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=5)
        self.search_entry.bind("<Return>", self.search_offers)

        self.search_button = ttk.Button(search_frame, text="Search", command=self.search_offers)
        self.search_button.pack(side=tk.LEFT, padx=5)

        # Results frame
        results_frame = ttk.Frame(main_frame)
        results_frame.pack(fill=tk.BOTH, expand=True, pady=5)

        self.results_text = tk.Text(results_frame, wrap=tk.WORD, state="disabled")
        self.results_text.pack(fill=tk.BOTH, expand=True)

        # Configure the hyperlink tag style. The click binding is now set dynamically.
        self.results_text.tag_configure("hyperlink", foreground="blue", underline=True)
        self.results_text.tag_bind("hyperlink", "<Enter>", self._enter_hyperlink)
        self.results_text.tag_bind("hyperlink", "<Leave>", self._leave_hyperlink)

    def setup_credit_card_offers_tab(self):
        cc_frame = ttk.Frame(self.tab2, padding="10")
        cc_frame.pack(fill=tk.BOTH, expand=True)

        instructions = "Click on your credit card provider below to open their website. Log in to your account to view and activate your cash back offers."
        instructions_label = ttk.Label(cc_frame, text=instructions, wraplength=750, justify=tk.LEFT)
        instructions_label.pack(pady=10, fill=tk.X)

        # Credit card providers
        providers = {
            "Chase": "https://www.chase.com/myaccount/dashboard",
            "American Express": "https://www.americanexpress.com/en-us/account/login",
            "Bank of America": "https://www.bankofamerica.com/",
            "Capital One": "https://www.capitalone.com/",
            "Citi": "https://www.citi.com/",
            "Discover": "https://www.discover.com/"
        }

        buttons_frame = ttk.Frame(cc_frame)
        buttons_frame.pack(fill=tk.X)

        for name, url in providers.items():
            button = ttk.Button(buttons_frame, text=name, command=lambda u=url: self.open_link(u))
            button.pack(pady=5, fill=tk.X)

    def open_link(self, url):
        webbrowser.open(url)

    def _enter_hyperlink(self, event):
        self.results_text.config(cursor="hand2")

    def _leave_hyperlink(self, event):
        self.results_text.config(cursor="")

    def _click_hyperlink(self, url):
        # This method now accepts the URL directly, preventing the race condition.
        print(f"Opening link: {url}")
        webbrowser.open(url)

    def search_offers(self, event=None):
        store_name = self.search_entry.get()
        if not store_name:
            return

        self.search_button.config(state="disabled")
        self.results_text.config(state="normal")
        self.results_text.delete("1.0", tk.END)
        self.results_text.insert(tk.END, f"Searching for offers for: {store_name}...\n")
        self.results_text.config(state="disabled")

        thread = threading.Thread(target=self.run_scraper, args=(store_name,))
        thread.start()

    def run_scraper(self, store_name):
        result = scrape_rakuten(store_name)
        formatted_name = format_store_name_for_url(store_name)
        # The link is now a local variable, not a problematic instance variable.
        link = f"https://www.rakuten.com/shop/{formatted_name}"
        self.after(0, self.update_results, result, link)

    def update_results(self, result, link):
        self.results_text.config(state="normal")
        self.results_text.delete("1.0", tk.END)
        self.results_text.insert(tk.END, result + "\n\n")

        # Dynamically bind the click event with a lambda to capture the correct link
        self.results_text.tag_bind("hyperlink", "<Button-1>", lambda e, u=link: self._click_hyperlink(u))

        self.results_text.insert(tk.END, "Click here to go to the store page", "hyperlink")
        self.results_text.config(state="disabled")
        self.search_button.config(state="normal")

if __name__ == "__main__":
    app = CashbackApp()
    app.mainloop()