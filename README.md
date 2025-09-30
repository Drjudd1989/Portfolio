# Conversational RAG Web Application with Google Gemini and Wikipedia

This project is a web-based implementation of a conversational Retrieval-Augmented Generation (RAG) system. It uses Google's Gemini Pro as the Large Language Model (LLM) and Wikipedia as the external knowledge base. The web interface is built with Gradio and supports back-and-forth conversations.

## How it works

The system takes a user's question from a chat interface, searches for relevant information on Wikipedia, and then uses that context, along with the history of the conversation, to generate a contextual and informed answer using Google Gemini Pro. The answer is then displayed back to the user in the chat interface, and the conversation can continue.

## Prerequisites

- Python 3.7 or higher
- A Google Gemini API key

## Setup

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/your-username/simple-rag-gemini-wikipedia.git
    cd simple-rag-gemini-wikipedia
    ```

2.  **Install the dependencies:**

    ```bash
    pip install -r requirements.txt
    ```

3.  **Create a `.env` file:**

    Create a file named `.env` in the root of the project directory and add your Google Gemini API key to it:

    ```
    GEMINI_API_KEY=your_gemini_api_key
    ```

    Replace `your_gemini_api_key` with your actual API key.

## Usage

To run the conversational RAG web application, execute the following command in your terminal:

```bash
python rag_from_wikipedia.py
```

This will start a local web server. You can access the application by opening the URL provided in the terminal (usually `http://127.0.0.1:7860`) in your web browser.

The chat interface allows you to have a continuous conversation. You can ask follow-up questions, and the model will use the history to understand the context.

### Example

Once the application is running, you will see a chat interface.

**User:** `What is a RAG system?`

**Assistant:** `A Retrieval-Augmented Generation (RAG) system is a type of artificial intelligence model that combines a retrieval system with a generative model. The retrieval system first finds relevant information from a large dataset, such as Wikipedia, and then the generative model uses that information to create a more accurate and contextually relevant answer to a user's question.`

**User:** `How does it help with hallucinations?`

**Assistant:** `RAG helps reduce hallucinations by grounding the generative model in factual information retrieved from an external knowledge base. By providing relevant and verifiable context, the model is less likely to generate false or misleading information, as its responses are based on the provided text rather than just its internal pre-trained knowledge.`