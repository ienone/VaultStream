"""Convert Telegram HTML entities without losing message line breaks."""
from bs4 import BeautifulSoup, NavigableString, Tag
from markdownify import markdownify


def telegram_html_to_markdown(value: str) -> str:
    soup = BeautifulSoup(value, 'html.parser')
    for tag in soup.find_all(['b', 'strong', 'i', 'em', 's', 'del']):
        tag.name = {'b': 'strong', 'i': 'em', 's': 'del'}.get(tag.name, tag.name)
    # Adjacent entity ranges must form one span, not ambiguous **** delimiters.
    for tag in list(soup.find_all(['strong', 'em', 'del'])):
        if tag.parent is None:
            continue
        while isinstance(tag.next_sibling, Tag) and tag.next_sibling.name == tag.name:
            sibling = tag.next_sibling
            for child in list(sibling.contents):
                tag.append(child.extract())
            sibling.decompose()
    for node in list(soup.find_all(string=True)):
        if '\n' not in node or node.find_parent(['pre', 'code']):
            continue
        for index, part in enumerate(str(node).split('\n')):
            if index:
                node.insert_before(soup.new_tag('br'))
            node.insert_before(NavigableString(part))
        node.extract()
    return markdownify(str(soup), heading_style='ATX').strip()
