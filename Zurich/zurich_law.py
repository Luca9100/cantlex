import json
import html
import urllib.request
import re

def clean_text(text):
    """Fix encoding issues and decode HTML entities safely."""
    if not text:
        return ""
    text = html.unescape(text)
    try:
        return text.encode('latin1').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text.strip()

def remove_parentheses_content(text):
    """Remove any content inside parentheses, including the parentheses."""
    return re.sub(r"\s*\([^)]*\)", "", text).strip()

def get_latest_active_version(versions):
    """Get the latest active version or fallback to the most recent one."""
    if not versions:
        return {}

    active = [v for v in versions if v.get("in_force")]
    if active:
        return active[0]

    sorted_versions = sorted(versions, key=lambda v: v.get("publikationsdatum", ""), reverse=True)
    return sorted_versions[0] if sorted_versions else {}

def extract_abbreviation_url_map_from_web(url, output_json_path=None):
    with urllib.request.urlopen(url) as response:
        data = json.load(response)

    output = []

    for entry in data:
        version = get_latest_active_version(entry.get("versions", []))
        zhlaw_url = version.get("zhlaw_url_dynamic") or entry.get("zhlaw_url_dynamic")
        zhlaw_url = zhlaw_url.strip() if zhlaw_url else ""
        if not zhlaw_url:
            continue

        title = clean_text(entry.get("erlasstitel", ""))
        title = remove_parentheses_content(title)

        abkuerzung = clean_text(entry.get("abkuerzung", ""))

        if abkuerzung:
            output.append({
                "abbreviation": abkuerzung,
                "url": zhlaw_url,
                "title": title,
                "canton": "ZH",
                "language": "de"
            })

    # Remove duplicates
    seen = set()
    unique_output = []
    for item in output:
        key = (item["abbreviation"], item["url"])
        if key not in seen:
            seen.add(key)
            unique_output.append(item)

    if output_json_path:
        with open(output_json_path, 'w', encoding='utf-8') as out:
            json.dump(unique_output, out, ensure_ascii=False, indent=2)

    return unique_output

# Example usage
if __name__ == "__main__":
    url = "https://www.zhlaw.ch/collection-metadata-zh.json"
    output_file = "zurich_laws_output.json"

    result = extract_abbreviation_url_map_from_web(url, output_json_path=output_file)
    print(json.dumps(result[:5], indent=2, ensure_ascii=False))  # Preview first 5
