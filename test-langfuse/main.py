import os
from langfuse import get_client
from langfuse.openai import OpenAI

os.environ["LANGFUSE_PUBLIC_KEY"] = "pk-lf.."
os.environ["LANGFUSE_SECRET_KEY"] = "sk-lf-.."
os.environ["LANGFUSE_BASE_URL"] = "http://localhost:3000"  # 🇪🇺 EU region
# os.environ["LANGFUSE_BASE_URL"] = "https://us.cloud.langfuse.com" # 🇺🇸 US region

os.environ["ANTHROPIC_API_KEY"] = "sk-.."
from anthropic import Anthropic


def main():

    client = OpenAI(
        api_key=os.environ.get("ANTHROPIC_API_KEY"),  # Your Anthropic API key
        base_url="https://api.anthropic.com/v1/",  # Anthropic's API endpoint
    )

    response = client.chat.completions.create(
        model="claude-opus-4-20250514",  # Anthropic model name
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Who are you?"},
        ],
    )

    print(response.choices[0].message.content)


if __name__ == "__main__":
    main()
