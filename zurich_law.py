import json
import html
import pandas as pd
import unicodedata

def clean_text(text):
    """Fix encoding issues and decode HTML entities."""
    if not text:
        return ""
    text = html.unescape(text)
    try:
        text = text.encode('latin1').decode('utf-8')
    except UnicodeEncodeError:
        pass
    return text.strip()

def extract_data(json_file_path, output_csv_path=None):
    with open(json_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    results = []
    for entry in data:
        erlasstitel = clean_text(entry.get("erlasstitel", ""))
        abkuerzung = clean_text(entry.get("abkuerzung", ""))
        kurztitel = clean_text(entry.get("kurztitel", ""))
        zhlaw_url = entry.get("zhlaw_url_dynamic", "")

        versions = entry.get("versions", [])
        law_page_url = versions[0].get("law_page_url", "") if versions else ""
        law_text_url = versions[0].get("law_text_url", "") if versions else ""

        results.append({
            "erlasstitel": erlasstitel,
            "abkuerzung": abkuerzung,
            "kurztitel": kurztitel,
            "zhlaw_url_dynamic": zhlaw_url,
            "law_page_url": law_page_url,
            "law_text_url": law_text_url
        })

    # Create DataFrame
    df = pd.DataFrame(results)

    # Optional: Export to CSV
    if output_csv_path:
        df.to_csv(output_csv_path, index=False, encoding='utf-8')

    return df

# Example usage
if __name__ == "__main__":
    json_file = "laws.json"  # Replace with your actual path
    output_csv = "extracted_laws.csv"

    df = extract_data(json_file, output_csv_path=output_csv)

    # Print preview
    print(df.head())
